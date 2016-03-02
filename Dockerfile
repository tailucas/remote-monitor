FROM resin/rpi-raspbian:wheezy-20160113

MAINTAINER db2inst1 <db2inst1@webafrica.org.za>
LABEL Description="remote_monitor" Vendor="db2inst1" Version="1.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
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
    wget

COPY ./config/pip_freeze /tmp/
# pip 8
RUN python pipstrap.py
RUN pip install -r /tmp/pip_freeze
# show outdated packages since the freeze
RUN pip list --outdated

# ssh, zmq
EXPOSE 22 5556 5558

# sshd configuration
RUN mkdir /var/run/sshd
RUN mkdir /root/.ssh/

COPY . /app
COPY ./entrypoint.sh /

# awslogs
RUN wget https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O /app/awslogs-agent-setup.py
RUN python /app/awslogs-agent-setup.py -n -r "eu-west-1" -c /app/config/awslogs-config
# remove the service and nanny (supervisor does this)
RUN update-rc.d awslogs remove
RUN rm -f /etc/cron.d/awslogs

ENTRYPOINT ["/entrypoint.sh"]
