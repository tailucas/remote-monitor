#!/bin/bash
set -eux

# set the timezone
tzupdate


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

# remove unnecessary kernel drivers
rmmod w1_gpio||true

# groups
groupadd -f -r "${APP_GROUP}"

# application configuration (no tee for secrets)
cat /app/config/remote_monitor.conf | python /app/config_interpol > /app/remote_monitor.conf

# non-root users
useradd -r -g "${APP_GROUP}" "${APP_USER}"
chown -R "${APP_USER}:${APP_GROUP}" /app/
# non-volatile storage
chown -R "${APP_USER}:${APP_GROUP}" /data/
# so app can make the noise
adduser "${APP_USER}" audio
# so app can interact with the serial device
adduser "${APP_USER}" dialout
# so app can god mode
adduser "${APP_USER}" sudo
echo "%${APP_GROUP}  ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${APP_GROUP}"
chmod 0440 "/etc/sudoers.d/${APP_GROUP}"

# start d-bus, let supervisord do the rest
/etc/init.d/dbus start

# I'm the supervisor
cat /app/config/supervisord.conf | python /app/config_interpol | tee /etc/supervisor/conf.d/supervisord.conf
/usr/bin/supervisord