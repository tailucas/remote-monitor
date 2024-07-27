#!/usr/bin/env bash
set -eu
set -o pipefail

while [ -n "${NO_START:-}" ]; do
  echo "${BALENA_DEVICE_NAME_AT_INIT} (${BALENA_DEVICE_ARCH} ${BALENA_DEVICE_TYPE}) is in NoStart (unset NO_START variable to start)."
  curl -s -X GET --header "Content-Type:application/json" "${BALENA_SUPERVISOR_ADDRESS}/v1/device?apikey=${BALENA_SUPERVISOR_API_KEY}" | jq
  sleep 3600
done

if [ -n "${TEST_ON_START_ADDRESS:-}" ]; then
  nc -zvw2 "${TEST_ON_START_ADDRESS}" "${TEST_ON_START_PORT:-80}"
fi

set -x

# cron

# combine crons and register (note missing users)
rm -f /opt/app/config/app_crontabs
for c in /opt/app/config/cron/*; do
  cat "$c" >> /opt/app/config/app_crontabs
done
# register user crons
crontab -u app /opt/app/config/app_crontabs

# rsyslog
if [ -n "${RSYSLOG_SERVER:-}" ]; then
  mkdir -p /etc/rsyslog.d/
  cat << EOF > /etc/rsyslog.d/custom.conf
\$PreserveFQDN on
\$ActionQueueFileName queue
\$ActionQueueMaxDiskSpace 1g
\$ActionQueueSaveOnShutdown on
\$ActionQueueType LinkedList
\$ActionResumeRetryCount -1
\$template MyTemplate, "<%pri%> %timestamp% ${RESIN_DEVICE_NAME_AT_INIT} %syslogtag% %msg%\n"
\$ActionForwardDefaultTemplate MyTemplate
*.*;auth,authpriv.none,cron.none	@${RSYSLOG_SERVER}${RSYSLOG_TEMPLATE:-}
EOF
fi
# application configuration (no tee for secrets)
/opt/app/config_interpol < /opt/app/config/app.conf > /opt/app/app.conf
# service configuration
cp /opt/app/config/supervisord.conf /opt/app/supervisord.conf

# job environment
printenv | sed 's/=\(.*\)/="\1"/' >> /opt/app/cron.env

# load I2C
modprobe i2c-dev

# show what i2c buses are available, and grant file permissions
for i in $(/usr/sbin/i2cdetect -l | cut -f1); do
  chown app "/dev/${i}"
done

# run user permissions
chown app:app /opt/app/
chown -R app:app /data/
# FIXME: run as unpriviledged user
/usr/sbin/rsyslogd
# replace this entrypoint with process manager
exec env supervisord -n -c /opt/app/supervisord.conf
