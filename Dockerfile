FROM resin/raspberrypi-debian:wheezy

MAINTAINER db2inst1 <db2inst1@webafrica.org.za>
LABEL Description="remote_monitor" Vendor="db2inst1" Version="1.0"

COPY ./pipstrap.py /tmp/

RUN apt-get clean && apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    cpp \
    cron \
    curl \
    dbus \
    g++ \
    gcc \
    git \
    i2c-tools \
    less \
    libffi-dev \
    libssl-dev \
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
    supervisor \
    vim \
    wget \
    # pip 8
    && python /tmp/pipstrap.py

# ssh, zmq
EXPOSE 22 5556 5558

# sshd configuration
RUN mkdir /var/run/sshd
RUN mkdir /root/.ssh/

COPY . /app
COPY ./entrypoint.sh /

COPY ./config/pip_freeze /tmp/
RUN pip install -r /tmp/pip_freeze
# show outdated packages since the freeze
RUN pip list --outdated

ENTRYPOINT ["/entrypoint.sh"]
