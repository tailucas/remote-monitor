FROM balenalib/raspberry-pi-debian:bullseye-run
ENV INITSYSTEM on
ENV container docker

ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true

RUN apt-get clean && apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cron \
    dbus \
    git \
    htop \
    i2c-tools \
    lsof \
    openssh-server \
    patch \
    python3-certifi \
    python3-dbus \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-smbus \
    python3-venv \
    python3-wheel \
    rsyslog \
    strace \
    supervisor \
    tree \
    vim \
    wget

# python3 default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

COPY . /opt/app

# setup
RUN /opt/app/app_setup.sh

STOPSIGNAL 37
# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/opt/app/entrypoint.sh"]
