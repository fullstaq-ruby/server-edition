FROM debian:9

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

RUN set -x && \
    apt update && \
    apt install -y autoconf bison build-essential ccache \
        libssl-dev libyaml-dev libreadline-dev zlib1g-dev \
        libncurses5-dev libffi-dev libgdbm3 libgdbm-dev && \
    addgroup --gid 9999 builder && \
    adduser --uid 9999 --gid 9999 --disabled-password --gecos Builder builder && \
    usermod -L builder && \
    apt clean && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
