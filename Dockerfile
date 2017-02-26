FROM resin/raspberrypi-debian:latest
ENV INITSYSTEM on

MAINTAINER db2inst1 <db2inst1@webafrica.org.za>
LABEL Description="remote_monitor" Vendor="db2inst1" Version="1.0"

COPY ./pipstrap.py /tmp/
RUN apt-get clean && apt-get update && apt-get install -y --no-install-recommends \
    arduino \
    ca-certificates \
    cpp \
    cron \
    curl \
    dbus \
    g++ \
    gcc \
    git \
    htop \
    i2c-tools \
    less \
    libffi-dev \
    libssl-dev \
    lsof \
    make \
    man-db \
    manpages \
    net-tools \
    openssh-server \
    openssl \
    psmisc \
    python-dbus \
    python-pip \
    python2.7 \
    python2.7-dev \
    python-smbus \
    rsyslog \
    ssl-cert \
    strace \
    vim \
    wavemon \
    wget \
    # pip 8
    && python /tmp/pipstrap.py

COPY ./config/requirements.txt /tmp/
RUN pip install -r /tmp/requirements.txt

COPY . /app

# build the Arduino image
WORKDIR /app/sampler
RUN ARDUINODIR=/usr/share/arduino \
    BOARD=uno \
    SERIALDEV=/dev/ttyACM0 \
    make
WORKDIR /

# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/app/entrypoint.sh"]