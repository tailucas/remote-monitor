#!/usr/bin/env sh
set -eu
set -o pipefail

while [ -n "${NO_START:-}" ]; do
  echo "${BALENA_DEVICE_NAME_AT_INIT} (${BALENA_DEVICE_ARCH} ${BALENA_DEVICE_TYPE}) is in NoStart (unset NO_START variable to start)."
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
/opt/app/pylib/config_interpol < /opt/app/config/app.conf > /opt/app/app.conf
# service configuration
cp /opt/app/config/supervisord.conf /opt/app/supervisord.conf

# run-as user permissions
chown app:app /opt/app/
chown -R app:app /data/
chown app /dev/i2c-1
# FIXME: run as unpriviledged user
/usr/sbin/rsyslogd
# replace this entrypoint with process manager
exec su-exec app env supervisord -n -c /opt/app/supervisord.conf
