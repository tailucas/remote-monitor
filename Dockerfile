FROM debian:trixie-slim
ARG DEBIAN_FRONTEND=noninteractive
# generate correct locales
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        locales \
        curl
ARG LANG
ENV LANG=$LANG
ARG LANGUAGE
ENV LANGUAGE=$LANGUAGE
ARG LC_ALL
ENV LC_ALL=$LC_ALL
ARG ENCODING
RUN localedef -i ${LANGUAGE} -c -f $ENCODING -A /usr/share/locale/locale.alias ${LANG} \
    && update-locale LANG=${LANG}
# tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    # Add the tailscale repository
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
# force architecture for emulated builds
RUN dpkg --add-architecture armhf
# remaining system packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        cron \
        dbus \
        dnsdiag \
        dnsutils \
        g++ \
        gcc \
        # 3rd party libs
        git \
        gosu \
        i2c-tools \
        inetutils-traceroute \
        iproute2 \
        iputils-ping \
        jq \
        # modprobe
        kmod \
        lsof \
        # cffi for cryptography
        libffi-dev \
        libssl-dev \
        libzmq3-dev \
        make \
        netcat-openbsd \
        openresolv \
        rsyslog \
        pkg-config \
        # provides uptime
        procps \
        python3-dev \
        supervisor \
        tailscale \
        tree \
        vim-tiny \
    && rm -rf /var/lib/apt/lists/*
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
# application directory
WORKDIR /opt/app
COPY app/ ./app
COPY config/ ./config
# user scripts
COPY dot_env_setup.sh \
    entrypoint.sh \
    healthchecks_heartbeat.sh \
    python_setup.sh \
    rust_setup.sh \
    pyproject.toml \
    uv.lock \
    # for uv
    README.md ./
# permission to modify Python dependency list
RUN chown app:app /opt/app/uv.lock
# setup as run user
# FIXME entrypoint items that run as root
# USER app
ENV HOME=/home/app
# install rust for cryptography wheel builds
ENV PATH="${PATH}:${HOME}/.local/bin:${HOME}/.cargo/bin"
RUN /opt/app/rust_setup.sh
RUN /opt/app/python_setup.sh
RUN chown -R app:app /home/app/.cache/uv/
STOPSIGNAL 37
# ssh, zmq
EXPOSE 22 5556 5558
CMD ["/opt/app/entrypoint.sh"]