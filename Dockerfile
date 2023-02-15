FROM balenalib/raspberry-pi-alpine-python:latest-latest-run

RUN apk update \
    && apk upgrade \
    && apk --no-cache add \
        cargo \
        curl \
        dcron \
        # zmq wheel
        g++ \
        # 3rd party libs
        git \
        # cron non-root
        libcap \
        libffi-dev \
        openssl-dev \
        rsyslog \
        rust \
        su-exec \
        supervisor

COPY . /opt/app
WORKDIR /opt/app

RUN mkdir -p /home/app/
RUN addgroup app
RUN adduser -G app -h /home/app -D app
RUN chown app:app /home/app/
RUN chown app:app /opt/app/
RUN mkdir -p /etc/rsyslog.d/
RUN touch /etc/rsyslog.d/custom.conf
RUN chown -R app:app /etc/rsyslog.d/

# setup as root
RUN /opt/app/app_setup.sh
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
