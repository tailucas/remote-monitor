#!/bin/bash
set -eu
set -o pipefail

# host heartbeat, must fail if variable is unset
echo "Installing heartbeat to ${HC_PING_URL}"
cp /opt/app/config/healthchecks_heartbeat /etc/cron.d/healthchecks_heartbeat

while [ -n "${STAY_DOWN:-}" ]; do
  echo "${BALENA_DEVICE_NAME_AT_INIT} (${BALENA_DEVICE_ARCH} ${BALENA_DEVICE_TYPE}) is in StayDown (unset STAY_DOWN variable to start)."
  curl -s -X GET --header "Content-Type:application/json" "${BALENA_SUPERVISOR_ADDRESS}/v1/device?apikey=${BALENA_SUPERVISOR_API_KEY}" | jq
  sleep 3600
done

# Resin API key (prefer override from application/device environment)
export RESIN_API_KEY="${API_KEY_RESIN:-$RESIN_API_KEY}"
# root user access, prefer key
mkdir -p /root/.ssh/

echo "$(/opt/app/bin/python /opt/app/pylib/cred_tool <<< '{"s": {"opitem": "SSH", "opfield": ".password"}}')" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
if [ -n "${ROOT_PASSWORD:-}" ]; then
  echo "root:${ROOT_PASSWORD}" | chpasswd
  sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  # SSH login fix. Otherwise user is kicked off after login
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi
# https://bugs.launchpad.net/ubuntu/+source/openssh/+bug/45234
mkdir -p /run/sshd
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

# Create /etc/docker.env
if [ ! -e /etc/docker.env ]; then
  # https://github.com/balena-io-library/base-images/blob/b4fc5c21dd1e28c21e5661f65809c90ed7605fe6/examples/INITSYSTEM/systemd/systemd/entry.sh
  for var in $(compgen -e); do
    printf '%q=%q\n' "$var" "${!var}"
  done > /etc/docker.env
fi

set -x

# attempt to remove these kernel modules
for module in "${REMOVE_KERNEL_MODULES:-}"; do
  rmmod $module || true
done

# Run user
export APP_USER="${APP_USER:-app}"
export APP_GROUP="${APP_GROUP:-app}"

# groups
groupadd -f -r "${APP_GROUP}"

# non-root users
id -u "${APP_USER}" || useradd -r -g "${APP_GROUP}" "${APP_USER}"
chown "${APP_USER}:${APP_GROUP}" /opt/app/*
# non-volatile storage
chown -R "${APP_USER}:${APP_GROUP}" /data/
# home
mkdir -p "/home/${APP_USER}/.aws/"
chown -R "${APP_USER}:${APP_GROUP}" "/home/${APP_USER}/"
# AWS configuration (no tee for secrets)
cat /opt/app/config/aws-config | /opt/app/pylib/config_interpol > "/home/${APP_USER}/.aws/config"
# patch botoflow to work-around
# AttributeError: 'Endpoint' object has no attribute 'timeout'
PY_BASE_WORKER="$(find /opt/app/ -name base_worker.py)"
patch -f -u "$PY_BASE_WORKER" -i /opt/app/config/base_worker.patch || true

TZ_CACHE=/data/localtime
# a valid symlink
if [ -h "$TZ_CACHE" ] && [ -e "$TZ_CACHE" ]; then
  cp -a "$TZ_CACHE" /etc/localtime
fi
# set the timezone
(tzupdate && cp -a /etc/localtime "$TZ_CACHE") || [ -e "$TZ_CACHE" ]

# reset hostname (in a way that works)
# https://forums.resin.io/t/read-only-file-system-when-calling-setstatichostname-via-dbus/1578/10
curl -X PATCH --header "Content-Type:application/json" \
  --data '{"network": {"hostname": "'${RESIN_DEVICE_NAME_AT_INIT}'"}}' \
  "$RESIN_SUPERVISOR_ADDRESS/v1/device/host-config?apikey=$RESIN_SUPERVISOR_API_KEY"
echo "$RESIN_DEVICE_NAME_AT_INIT" > /etc/hostname
echo "127.0.1.1 ${RESIN_DEVICE_NAME_AT_INIT}" >> /etc/hosts

# rsyslog
if [ -n "${RSYSLOG_SERVER:-}" ]; then
  cat << EOF > /etc/rsyslog.d/custom.conf
\$PreserveFQDN on
\$ActionQueueFileName queue
\$ActionQueueMaxDiskSpace 1g
\$ActionQueueSaveOnShutdown on
\$ActionQueueType LinkedList
\$ActionResumeRetryCount -1
*.* @${RSYSLOG_SERVER}${RSYSLOG_TEMPLATE:-}
EOF
fi
# logentries
if [ -n "${RSYSLOG_LOGENTRIES:-}" ]; then
  set +x
  RSYSLOG_LOGENTRIES_TOKEN="$(/opt/app/bin/python /opt/app/pylib/cred_tool <<< '{"s": {"opitem": "Logentries", "opfield": "${APP_NAME}.token"}}')"
  if [ -n "${RSYSLOG_LOGENTRIES_TOKEN:-}" ] && ! grep -q "$RSYSLOG_LOGENTRIES_TOKEN" /etc/rsyslog.d/logentries.conf; then
    echo "\$template LogentriesFormat,\"${RSYSLOG_LOGENTRIES_TOKEN} %HOSTNAME% %syslogtag%%msg%\n\"" >> /etc/rsyslog.d/logentries.conf
    RSYSLOG_TEMPLATE=";LogentriesFormat"
  fi
  echo "*.*          @@${RSYSLOG_LOGENTRIES_SERVER}${RSYSLOG_TEMPLATE:-}" >> /etc/rsyslog.d/logentries.conf
  unset RSYSLOG_LOGENTRIES_TOKEN
  set -x
fi
# bounce rsyslog for the new data
if find /etc/rsyslog.d/ -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
  service rsyslog restart
fi

# configuration update
for iface in wlan0 eth0; do
  export ETH0_IP="$(/sbin/ifconfig ${iface} | grep 'inet' | awk '{ print $2 }' | cut -f2 -d ':')"
  if [ -n "$ETH0_IP" ]; then
    break
  fi
done
# application configuration (no tee for secrets)
cat /opt/app/config/app.conf | /opt/app/pylib/config_interpol > "/opt/app/${APP_NAME}.conf"
unset ETH0_IP

# load I2C
modprobe i2c-dev

# so app can do i2c
adduser "${APP_USER}" i2c
# so app can interact with the serial device
adduser "${APP_USER}" dialout

# show what i2c buses are available, and grant file permissions
for i in "$(/usr/sbin/i2cdetect -l | cut -f1)"; do
  chown "${APP_USER}" "/dev/${i}"
done

# Load app environment, overriding HOME and USER
# https://www.freedesktop.org/software/systemd/man/systemd.exec.html
cat /etc/docker.env | egrep -v "^HOME|^USER" > /opt/app/environment.env
echo "HOME=/data/" >> /opt/app/environment.env
echo "USER=${APP_USER}" >> /opt/app/environment.env

echo "export HISTFILE=/data/.bash_history" >> /etc/bash.bashrc

# systemd configuration
for systemdsvc in app; do
  if [ ! -e "/etc/systemd/system/${systemdsvc}.service" ]; then
    cat "/opt/app/config/systemd.${systemdsvc}.service" | /opt/app/pylib/config_interpol | tee "/etc/systemd/system/${systemdsvc}.service"
    chmod 664 "/etc/systemd/system/${systemdsvc}.service"
    systemctl enable "${systemdsvc}"
  fi
done

# replace this entrypoint with systemd init scope
exec env DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket /lib/systemd/systemd quiet systemd.show_status=0
