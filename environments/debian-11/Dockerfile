FROM debian:11

# Used to link container image to the repo:
# https://docs.github.com/en/free-pro-team@latest/packages/managing-container-images-with-github-container-registry/connecting-a-repository-to-a-container-image#connecting-a-repository-to-a-container-image-on-the-command-line
LABEL org.opencontainers.image.source https://github.com/fullstaq-ruby/server-edition

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

RUN set -x && \
    apt update && \
    apt install -y autoconf bison bzip2 build-essential \
        dpkg-dev curl ca-certificates \
        libssl-dev libyaml-dev libreadline-dev zlib1g-dev \
        libncurses5-dev libffi-dev libgdbm6 libgdbm-dev && \
    apt clean && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

# RUN curl -fsSLo sccache.tar.gz https://github.com/mozilla/sccache/releases/download/v0.3.0/sccache-v0.2.16-x86_64-unknown-linux-musl.tar.gz && \
#     tar xzf sccache.tar.gz && \
#     mv sccache-*/sccache /usr/local/bin/ && \
RUN curl -fsSLo sccache.gz https://github.com/FooBarWidget/sccache/releases/download/v0.2.16/sccache.gz && \
    gunzip sccache.gz && \
    mv sccache /usr/local/bin/ && \
    chmod +x /usr/local/bin/sccache && \
    chown root: /usr/local/bin/sccache && \
    rm -rf sccache-* && \
    mkdir /usr/local/lib/sccache && \
    echo '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/cc "$@"' > /usr/local/lib/sccache/cc && \
    echo '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/c++ "$@"' > /usr/local/lib/sccache/c++ && \
    echo '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/gcc "$@"' > /usr/local/lib/sccache/gcc && \
    echo '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/g++ "$@"' > /usr/local/lib/sccache/g++ && \
    chmod +x /usr/local/lib/sccache/* && \
    \
    curl -fsSLo /sbin/matchhostfsowner.gz https://github.com/FooBarWidget/matchhostfsowner/releases/download/v0.9.8/matchhostfsowner-0.9.8-x86_64-linux.gz && \
    gunzip /sbin/matchhostfsowner.gz && \
    chmod +x,+s /sbin/matchhostfsowner && \
    mkdir /etc/matchhostfsowner && \
    echo 'app_account: builder' > /etc/matchhostfsowner/config.yml && \
    \
    addgroup --gid 9999 builder && \
    adduser --uid 9999 --gid 9999 --disabled-password --gecos Builder builder && \
    usermod -L builder && \
    rm -rf /tmp/* /var/tmp/*

USER builder
ENTRYPOINT ["/sbin/matchhostfsowner"]
