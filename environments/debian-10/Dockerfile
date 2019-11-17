FROM debian:10

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

RUN set -x && \
    apt update && \
    apt install -y autoconf bison bzip2 build-essential \
        dpkg-dev curl ca-certificates ccache \
        libssl-dev libyaml-dev libreadline-dev zlib1g-dev \
        libncurses5-dev libffi-dev libgdbm6 libgdbm-dev && \
    \
    curl -sSLo /sbin/activatecontaineruid.gz https://github.com/fullstaq-labs/activatecontaineruid/releases/download/v0.9.2/activatecontaineruid-0.9.2-x86_64-linux.gz && \
    gunzip /sbin/activatecontaineruid.gz && \
    chmod +x,+s /sbin/activatecontaineruid && \
    mkdir /etc/activatecontaineruid && \
    echo 'app_account: builder' > /etc/activatecontaineruid/config.yml && \
    \
    addgroup --gid 9999 builder && \
    adduser --uid 9999 --gid 9999 --disabled-password --gecos Builder builder && \
    usermod -L builder && \
    apt clean && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

USER builder
ENTRYPOINT ["/sbin/activatecontaineruid"]
