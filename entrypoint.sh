#!/bin/bash
set -eu

# Resin API key
export RESIN_API_KEY="${RESIN_API_KEY:-$API_KEY_RESIN}"
# root user access, prefer key
if [ -n "$SSH_AUTHORIZED_KEY" ]; then
  echo "$SSH_AUTHORIZED_KEY" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
elif [ -n "$ROOT_PASSWORD" ]; then
  echo "root:${ROOT_PASSWORD}" | chpasswd
  sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  # SSH login fix. Otherwise user is kicked off after login
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
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


TZ_CACHE=/data/localtime
# a valid symlink
if [ -h "$TZ_CACHE" ] && [ -e "$TZ_CACHE" ]; then
  cp -a "$TZ_CACHE" /etc/localtime
else
  # set the timezone
  tzupdate
  cp -a /etc/localtime "$TZ_CACHE"
fi


# remote system logging
HN_CACHE=/data/hostname
if [ -e "$HN_CACHE" ]; then
  export DEVICE_NAME="$(cat "$HN_CACHE")"
else
  export DEVICE_NAME="$(python /app/resin --get-device-name)"
  echo "$DEVICE_NAME" > "$HN_CACHE"
fi
echo "$DEVICE_NAME" > /etc/hostname
# apply the new hostname
/etc/init.d/hostname.sh start
# update hosts
echo "127.0.1.1 ${DEVICE_NAME}" >> /etc/hosts
unset DEVICE_NAME

if [ -n "${RSYSLOG_SERVER:-}" ] && ! grep -q "$RSYSLOG_SERVER" /etc/rsyslog.conf; then
  echo "*.*          @${RSYSLOG_SERVER}" | tee -a /etc/rsyslog.conf
fi


# configuration update
export ETH0_IP="$(/sbin/ifconfig eth0 | grep 'inet addr' | awk '{ print $2 }' | cut -f2 -d ':')"
SUB_CACHE=/data/sub_src
if [ -e "$SUB_CACHE" ]; then
  export SUB_SRC="$(cat "$SUB_CACHE")"
else
  export SUB_SRC="$(python /app/resin --get-devices | grep -v "$ETH0_IP" | paste -d, -s)"
  echo "$SUB_SRC" > "$SUB_CACHE"
fi
# application configuration (no tee for secrets)
cat /app/config/app.conf | python /app/config_interpol > "/app/${APP_NAME}.conf"
unset ETH0_IP
unset SUB_SRC


# load I2C
modprobe i2c-dev

# so app can do i2c
adduser "${APP_USER}" i2c

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
    --data "{"appId": "$APP_ID"}" \
    "${RESIN_SUPERVISOR_ADDRESS}/v1/restart?apikey=${RESIN_SUPERVISOR_API_KEY}"
  chown "${APP_USER}" "/dev/${i}"
done

# I'm the supervisor
cat /app/config/supervisord.conf | python /app/config_interpol | tee /etc/supervisor/conf.d/supervisord.conf
/usr/bin/supervisord