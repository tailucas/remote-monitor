#!/bin/bash
set -eux

# Resin API key
export RESIN_API_KEY="${RESIN_API_KEY:-$API_KEY_RESIN}"

# Run user
export APP_USER="${APP_USER:-app}"
export APP_GROUP="${APP_GROUP:-app}"

TZ_CACHE=/data/localtime
# a valid symlink
if [ -h "$TZ_CACHE" ] && [ -e "$TZ_CACHE" ]; then
  cp -a "$TZ_CACHE" /etc/localtime
else
  # set the timezone
  tzupdate
  cp -a /etc/localtime "$TZ_CACHE"
fi

# load I2C
modprobe i2c-dev

# remote system logging
if [ -n "${RSYSLOG_HOSTNAME:-}" ]; then
  echo "${RSYSLOG_HOSTNAME}" > /etc/hostname
  # apply the new hostname
  /etc/init.d/hostname.sh start
  # update hosts
  echo "127.0.1.1 ${RSYSLOG_HOSTNAME}" >> /etc/hosts
fi
if [ -n "${RSYSLOG_SERVER:-}" ]; then
  echo "*.*          @${RSYSLOG_SERVER}" | tee -a /etc/rsyslog.conf
fi

# root user access, try a cert
if [ -n "$SSH_AUTHORIZED_KEY" ]; then
  echo "$SSH_AUTHORIZED_KEY" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
else
  echo 'root:resin' | chpasswd
  sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
  # SSH login fix. Otherwise user is kicked off after login
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi

# groups
groupadd -f -r "${APP_GROUP}"

# application configuration (no tee for secrets)
cat /app/config/remote_monitor.conf | python /app/config_interpol > /app/remote_monitor.conf

# non-root users
id -u "${APP_USER}" || useradd -r -g "${APP_GROUP}" "${APP_USER}"
chown -R "${APP_USER}:${APP_GROUP}" /app/
# non-volatile storage
chown -R "${APP_USER}:${APP_GROUP}" /data/
# so app can do i2c
adduser "${APP_USER}" i2c

# show what i2c buses are available, and grant file permissions
for i in "$(/usr/sbin/i2cdetect -l | cut -f1)"; do
  # reboot to work around issue discussed here:
  # http://docs.resin.io/#/pages/hardware/i2c-and-spi.md
  #TODO remove app ID
  /usr/sbin/i2cdetect -y "$(cut -f2 -d '-' <<< $i)" || curl -X POST --header "Content-Type:application/json" \
    --data '{"appId": 5268}' \
    "${RESIN_SUPERVISOR_ADDRESS}/v1/restart?apikey=${RESIN_SUPERVISOR_API_KEY}"
  chown "${APP_USER}" "/dev/${i}"
done

# start d-bus, let supervisord do the rest
/etc/init.d/dbus start

# I'm the supervisor
cat /app/config/supervisord.conf | python /app/config_interpol | tee /etc/supervisor/conf.d/supervisord.conf
/usr/bin/supervisord