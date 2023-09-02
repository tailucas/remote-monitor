FROM balenalib/raspberry-pi-python:latest-latest-run

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        cron \
        # cron non-root
        rsyslog \
        # provides uptime
        procps \
        supervisor

# create no-password run-as user
RUN groupadd -f -r -g 999 app
# create run-as user
RUN useradd -r -u 999 -g 999 app
# user permissions
RUN adduser app audio
RUN adduser app video
# cron
RUN chmod u+s /usr/sbin/cron
# used by pip, awscli, app
RUN mkdir -p /home/app/.aws/ /opt/app/
# file system permissions
RUN chown app /var/log/
RUN chown app:app /opt/app/
RUN chown -R app:app /home/app/
# rsyslog
RUN mkdir -p /etc/rsyslog.d/
RUN touch /etc/rsyslog.d/custom.conf
RUN chown -R app:app /etc/rsyslog.d/

COPY . /opt/app
WORKDIR /opt/app

# setup as root
USER app
ENV PATH "${PATH}:/home/app/.local/bin"
ENV PIP_DEFAULT_TIMEOUT 60
ENV PIP_DISABLE_PIP_VERSION_CHECK 1
ENV PIP_NO_CACHE_DIR 1
RUN /opt/app/python_setup.sh
USER root
STOPSIGNAL 37
# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/opt/app/entrypoint.sh"]
