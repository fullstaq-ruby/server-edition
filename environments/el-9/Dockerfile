FROM rockylinux:9
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

# Used to link container image to the repo:
# https://docs.github.com/en/free-pro-team@latest/packages/managing-container-images-with-github-container-registry/connecting-a-repository-to-a-container-image#connecting-a-repository-to-a-container-image-on-the-command-line
LABEL org.opencontainers.image.source=https://github.com/fullstaq-ruby/server-edition

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

RUN set -x && \
    dnf install -y dnf-plugins-core epel-release && \
    dnf install -y --enablerepo epel --enablerepo devel --allowerasing \
        findutils gcc gcc-c++ make patch bzip2 curl autoconf automake \
        openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel \
        gdbm-devel ncurses-devel \
        rust-toolset && \
    dnf clean all && \
    rm -rf /tmp/* /var/tmp/*

RUN set -e; \
    case "$TARGETARCH" in \
        amd64) SCCACHE_ARCH=x86_64 ;; \
        arm64) SCCACHE_ARCH=aarch64 ;; \
        *) echo "Unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSLo sccache.tar.gz "https://github.com/mozilla/sccache/releases/download/v0.3.1/sccache-v0.3.1-${SCCACHE_ARCH}-unknown-linux-musl.tar.gz" && \
    tar xzf sccache.tar.gz && \
    mv sccache-*/sccache /usr/local/bin/ && \
    chmod +x /usr/local/bin/sccache && \
    chown root: /usr/local/bin/sccache && \
    rm -rf sccache-* && \
    mkdir /usr/local/lib/sccache && \
    echo -e '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/cc "$@"' > /usr/local/lib/sccache/cc && \
    echo -e '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/c++ "$@"' > /usr/local/lib/sccache/c++ && \
    echo -e '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/gcc "$@"' > /usr/local/lib/sccache/gcc && \
    echo -e '#!/bin/sh\nexec /usr/local/bin/sccache /usr/bin/g++ "$@"' > /usr/local/lib/sccache/g++ && \
    chmod +x /usr/local/lib/sccache/* && \
    case "$TARGETARCH" in \
        amd64) MHF_ARCH=x86_64 ;; \
        arm64) MHF_ARCH=aarch64 ;; \
    esac; \
    curl -fsSLo /sbin/matchhostfsowner.gz "https://github.com/FooBarWidget/matchhostfsowner/releases/download/v0.9.8/matchhostfsowner-0.9.8-${MHF_ARCH}-linux.gz" && \
    gunzip /sbin/matchhostfsowner.gz && \
    chmod +x,+s /sbin/matchhostfsowner && \
    mkdir /etc/matchhostfsowner && \
    echo 'app_account: builder' > /etc/matchhostfsowner/config.yml && \
    \
    groupadd --gid 9999 builder && \
    adduser --uid 9999 --gid 9999 --password '#' builder && \
    rm -rf /tmp/* /var/tmp/*

USER builder
ENTRYPOINT ["/sbin/matchhostfsowner"]
