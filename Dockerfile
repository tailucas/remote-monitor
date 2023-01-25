FROM balenalib/raspberry-pi-alpine-python:latest-latest-run

RUN apk update \
    && apk upgrade \
    && apk --no-cache add \
        curl \
        dcron \
        # zmq wheel
        g++ \
        # 3rd party libs
        git \
        rsyslog \
        supervisor

COPY . /opt/app

# setup
RUN /opt/app/app_setup.sh

RUN mkdir -p /home/app/
RUN addgroup app
RUN adduser -G app -h /home/app -D app
RUN chown app:app /home/app/
RUN chown app:app /opt/app/

# cron
# heartbeat (note missing user from cron configuration)
RUN crontab /opt/app/config/healthchecks_heartbeat

STOPSIGNAL 37
# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/opt/app/entrypoint.sh"]
