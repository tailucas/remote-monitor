FROM resin/raspberrypi-debian:latest
ENV INITSYSTEM on

MAINTAINER db2inst1 <db2inst1@webafrica.org.za>
LABEL Description="remote_monitor" Vendor="db2inst1" Version="1.0"

COPY ./pipstrap.py /tmp/
# http://unix.stackexchange.com/questions/339132/reinstall-man-pages-fix-man
RUN rm -f /etc/dpkg/dpkg.cfg.d/01_nodoc
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
    ifupdown \
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

# Resin systemd
COPY ./config/systemd.launch.service /etc/systemd/system/launch.service.d/app_override.conf

# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/app/entrypoint.sh"]