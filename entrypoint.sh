#!/usr/bin/env sh
set -eu
set -o pipefail

while [ -n "${STAY_DOWN:-}" ]; do
  echo "${BALENA_DEVICE_NAME_AT_INIT} (${BALENA_DEVICE_ARCH} ${BALENA_DEVICE_TYPE}) is in StayDown (unset STAY_DOWN variable to start)."
  curl -s -X GET --header "Content-Type:application/json" "${BALENA_SUPERVISOR_ADDRESS}/v1/device?apikey=${BALENA_SUPERVISOR_API_KEY}" | jq
  sleep 3600
done

set -x

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
*.* @${RSYSLOG_SERVER}${RSYSLOG_TEMPLATE:-}
EOF
fi
# application configuration (no tee for secrets)
cat /opt/app/config/app.conf | /opt/app/pylib/config_interpol > "/opt/app/${APP_NAME}.conf"
# service configuration
cat /opt/app/config/supervisord.conf | /opt/app/pylib/config_interpol > /opt/app/supervisord.conf

# run-as user permissions
chown app:app /opt/app/
chown app /dev/i2c-1
# replace this entrypoint with process manager
exec env supervisord -n -c /opt/app/supervisord.conf
