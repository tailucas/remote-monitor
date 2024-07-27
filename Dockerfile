FROM balenalib/raspberry-pi-python:latest-latest-run

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        curl \
        cron \
        dbus \
        g++ \
        gcc \
        # 3rd party libs
        git \
        i2c-tools \
        jq \
        # cffi for cryptography
        libffi-dev \
        libssl-dev \
        libzmq3-dev \
        make \
        netcat \
        rsyslog \
        pkg-config \
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
# so app can do i2c
RUN adduser app i2c
# so app can interact with a serial device
RUN adduser app dialout
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
# rust

COPY . /opt/app
WORKDIR /opt/app
# setup as run user
USER app
ENV HOME="/home/app/"
# install rust for cryptography wheel builds
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="${PATH}:/home/app/.local/bin:/home/app/.cargo/bin"
ENV PIP_DEFAULT_TIMEOUT 60
ENV PIP_DISABLE_PIP_VERSION_CHECK 1
ENV PIP_NO_CACHE_DIR 1
RUN /opt/app/python_setup.sh
USER root
STOPSIGNAL 37
# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/opt/app/entrypoint.sh"]
