#!/usr/bin/env sh
set -e

# cron

# non-root user
chown app:app /usr/sbin/crond
setcap cap_setgid=ep /usr/sbin/crond

# cron
# heartbeat (note missing user from cron configuration)
crontab -u app /opt/app/config/healthchecks_heartbeat
chown -R app:app /etc/crontabs/
