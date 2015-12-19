FROM resin/rpi-raspbian:wheezy

MAINTAINER db2inst1 <db2inst1@webafrica.org.za>
LABEL Description="remote_monitor" Vendor="db2inst1" Version="1.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    cpp \
    curl \
    dbus \
    g++ \
    gcc \
    git \
    i2c-tools \
    less \
    libffi-dev \
    libssl-dev \
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
    vim

COPY ./config/remote_monitor_pip /tmp/
# update pip
RUN pip install -U pip
RUN pip install --upgrade setuptools
RUN pip install -r /tmp/remote_monitor_pip
# show outdated packages since the freeze
RUN pip list --outdated

# zmq
EXPOSE 5556

# SSH
EXPOSE 22

# sshd configuration
RUN mkdir /var/run/sshd
RUN mkdir /root/.ssh/

COPY . /app
COPY ./entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
