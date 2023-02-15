#!/usr/bin/env sh
set -e

# cron

# non-root user
chown app:app /usr/sbin/crond
setcap cap_setgid=ep /usr/sbin/crond