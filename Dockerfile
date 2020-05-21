FROM balenalib/raspberry-pi-debian:stretch-run
ENV INITSYSTEM on
ENV container docker

MAINTAINER db2inst1 <db2inst1@webafrica.org.za>
LABEL Description="remote_monitor" Vendor="db2inst1" Version="1.0"

# http://unix.stackexchange.com/questions/339132/reinstall-man-pages-fix-man
RUN rm -f /etc/dpkg/dpkg.cfg.d/01_nodoc /etc/dpkg/dpkg.cfg.d/docker
RUN apt-get clean && apt-get update && apt-get install -y --no-install-recommends \
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
    libzmq3-dev \
    lsof \
    man-db \
    manpages \
    net-tools \
    openssh-server \
    openssl \
    psmisc \
    python3-dbus \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-smbus \
    python3-venv \
    rsyslog \
    ssl-cert \
    strace \
    systemd \
    tree \
    vim \
    wavemon \
    wget \
    && pip3 install \
        tzupdate

# python3 default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

COPY . /opt/app

# setup
RUN /opt/app/app_setup.sh

# systemd masks for containers
# https://github.com/balena-io-library/base-images/blob/master/examples/INITSYSTEM/systemd/systemd.v230/Dockerfile
RUN systemctl mask \
    dev-hugepages.mount \
    sys-fs-fuse-connections.mount \
    sys-kernel-config.mount \
    display-manager.service \
    getty@.service \
    systemd-logind.service \
    systemd-remount-fs.service \
    getty.target \
    graphical.target \
    kmod-static-nodes.service

STOPSIGNAL 37
# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/opt/app/entrypoint.sh"]