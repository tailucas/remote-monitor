#!/bin/bash
set -eu
set -o pipefail

# Resin API key
export RESIN_API_KEY="${RESIN_API_KEY:-$API_KEY_RESIN}"
# root user access, prefer key
mkdir /root/.ssh/
if [ -n "$SSH_AUTHORIZED_KEY" ]; then
  echo "$SSH_AUTHORIZED_KEY" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
elif [ -n "$ROOT_PASSWORD" ]; then
  echo "root:${ROOT_PASSWORD}" | chpasswd
  sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  # SSH login fix. Otherwise user is kicked off after login
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi
# reload sshd
service ssh reload

# aws code commit
if [ -n "${AWS_REPO_SSH_KEY_ID:-}" ]; then
  # ssh
  echo "$AWS_REPO_SSH_PRIVATE_KEY" | base64 -d > /root/.ssh/codecommit_rsa
  chmod 600 /root/.ssh/codecommit_rsa
  cat << EOF >> /root/.ssh/config
StrictHostKeyChecking=no
Host git-codecommit.*.amazonaws.com
  User $AWS_REPO_SSH_KEY_ID
  IdentityFile /root/.ssh/codecommit_rsa
EOF
  chmod 600 /root/.ssh/config
fi

set -x


# Run user
export APP_USER="${APP_USER:-app}"
export APP_GROUP="${APP_GROUP:-app}"

# groups
groupadd -f -r "${APP_GROUP}"

# non-root users
id -u "${APP_USER}" || useradd -r -g "${APP_GROUP}" "${APP_USER}"
chown -R "${APP_USER}:${APP_GROUP}" /app/
# non-volatile storage
chown -R "${APP_USER}:${APP_GROUP}" /data/
# pidfile
chown "${APP_USER}" /var/run/

TZ_CACHE=/data/localtime
# a valid symlink
if [ -h "$TZ_CACHE" ] && [ -e "$TZ_CACHE" ]; then
  cp -a "$TZ_CACHE" /etc/localtime
fi
# set the timezone
(tzupdate && cp -a /etc/localtime "$TZ_CACHE") || [ -e "$TZ_CACHE" ]

# remote system logging
HN_CACHE=/data/hostname
if [ -e "$HN_CACHE" ]; then
  DEVICE_NAME="$(cat "$HN_CACHE")"
  # reject if there is a space
  space_pattern=" |'"
  if [[ $DEVICE_NAME =~ $space_pattern ]]; then
    unset DEVICE_NAME
  else
    export DEVICE_NAME
  fi
fi
# refresh the device name and bail unless cached
export DEVICE_NAME="$(python /app/resin --get-device-name)" || [ -n "${DEVICE_NAME:-}" ]
echo "$DEVICE_NAME" > "$HN_CACHE"
echo "$DEVICE_NAME" > /etc/hostname
# apply the new hostname
hostnamectl set-hostname "$DEVICE_NAME"
# update hosts
echo "127.0.1.1 ${DEVICE_NAME}" >> /etc/hosts

cp /app/config/rsyslog.conf /etc/rsyslog.conf
if [ -n "${RSYSLOG_SERVER:-}" ]; then
  set +x
  if [ -n "${RSYSLOG_TOKEN:-}" ] && ! grep -q "$RSYSLOG_TOKEN" /etc/rsyslog.d/custom.conf; then
    echo "\$template LogentriesFormat,\"${RSYSLOG_TOKEN} %HOSTNAME% %syslogtag%%msg%\n\"" >> /etc/rsyslog.d/custom.conf
    RSYSLOG_TEMPLATE=";LogentriesFormat"
  fi
  echo "*.*          @@${RSYSLOG_SERVER}${RSYSLOG_TEMPLATE:-}" >> /etc/rsyslog.d/custom.conf
  set -x
fi
# bounce rsyslog with the new configuration
service rsyslog restart

# log archival (no tee for secrets)
if [ -d /var/awslogs/etc/ ]; then
  cat /var/awslogs/etc/aws.conf | python /app/config_interpol /app/config/aws.conf > /var/awslogs/etc/aws.conf.new
  mv /var/awslogs/etc/aws.conf /var/awslogs/etc/aws.conf.backup
  mv /var/awslogs/etc/aws.conf.new /var/awslogs/etc/aws.conf
fi

# configuration update
for iface in eth0 wlan0; do
  export ETH0_IP="$(/sbin/ifconfig ${iface} | grep 'inet addr' | awk '{ print $2 }' | cut -f2 -d ':')"
  if [ -n "$ETH0_IP" ]; then
    break
  fi
done
SUB_CACHE=/data/sub_src
if [ -e "$SUB_CACHE" ]; then
  export SUB_SRC="$(cat "$SUB_CACHE")"
fi
# get the latest sources and bail unless cached
export SUB_SRC="$(python /app/resin --get-devices | grep -v "$ETH0_IP" | paste -d, -s)" || [ -n "${SUB_SRC:-}" ]
echo "$SUB_SRC" > "$SUB_CACHE"
# application configuration (no tee for secrets)
cat /app/config/app.conf | python /app/config_interpol > "/app/${APP_NAME}.conf"
unset ETH0_IP
unset SUB_SRC


# load I2C
modprobe i2c-dev

# so app can do i2c
adduser "${APP_USER}" i2c
# so app can interact with the serial device
adduser "${APP_USER}" dialout

APP_ID_CACHE=/data/app_id
if [ -e $APP_ID_CACHE ]; then
  export APP_ID="$(cat "$APP_ID_CACHE")"
else
  APP_ID="$(python /app/resin --get-app-id)"
  echo "$APP_ID" > "$APP_ID_CACHE"
fi

# show what i2c buses are available, and grant file permissions
for i in "$(/usr/sbin/i2cdetect -l | cut -f1)"; do
  # reboot to work around issue discussed here:
  # http://docs.resin.io/#/pages/hardware/i2c-and-spi.md
  /usr/sbin/i2cdetect -y "$(cut -f2 -d '-' <<< $i)" || curl -X POST --header "Content-Type:application/json" \
    --data "{\"appId\": \"$APP_ID\"}" \
    "${RESIN_SUPERVISOR_ADDRESS}/v1/restart?apikey=${RESIN_SUPERVISOR_API_KEY}"
  chown "${APP_USER}" "/dev/${i}"
done

# sampler programming
diff /app/sampler/sampler.ino /data/sampler.ino || PROGRAMMER=1
if [ "${PROGRAMMER:-}" == "1" ]; then
  pushd /app/sampler
  export ARDUINODIR=/usr/share/arduino
  export BOARD=uno
  export SERIALDEV=/dev/ttyACM0
  make upload
  unset ARDUINODIR
  unset BOARD
  unset SERIALDEV
  unset PROGRAMMER
  cp sampler.ino /data/
  popd
fi

echo "export HISTFILE=/data/.bash_history" >> /etc/bash.bashrc

# systemd configuration
for systemdsvc in app; do
  if [ ! -e "/etc/systemd/system/${systemdsvc}.service" ]; then
    cat "/app/config/systemd.${systemdsvc}.service" | python /app/config_interpol | tee "/etc/systemd/system/${systemdsvc}.service"
    chmod 664 "/etc/systemd/system/${systemdsvc}.service"
    systemctl daemon-reload
    systemctl start "${systemdsvc}"&
  fi
done