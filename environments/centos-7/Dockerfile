FROM centos:7

# Used to link container image to the repo: 
# https://docs.github.com/en/free-pro-team@latest/packages/managing-container-images-with-github-container-registry/connecting-a-repository-to-a-container-image#connecting-a-repository-to-a-container-image-on-the-command-line
LABEL org.opencontainers.image.source https://github.com/fullstaq-labs/fullstaq-ruby-server-edition

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

RUN set -x && \
    yum install -y epel-release && \
    yum install -y --enablerepo epel \
        gcc gcc-c++ make patch bzip2 curl autoconf automake \
        openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel \
        gdbm-devel ncurses-devel ccache && \
    \
    curl -sSLo /sbin/activatecontaineruid.gz https://github.com/fullstaq-labs/activatecontaineruid/releases/download/v0.9.3/activatecontaineruid-0.9.3-x86_64-linux.gz && \
    gunzip /sbin/activatecontaineruid.gz && \
    chmod +x,+s /sbin/activatecontaineruid && \
    mkdir /etc/activatecontaineruid && \
    echo 'app_account: builder' > /etc/activatecontaineruid/config.yml && \
    \
    groupadd --gid 9999 builder && \
    adduser --uid 9999 --gid 9999 --password '#' builder && \
    yum clean all && \
    if ! test -e /usr/lib/ccache/cc; then \
        mkdir -p /usr/lib/ccache && \
        ln -s /usr/bin/ccache /usr/lib/ccache/cc && \
        ln -s /usr/bin/ccache /usr/lib/ccache/gcc && \
        ln -s /usr/bin/ccache /usr/lib/ccache/c++ && \
        ln -s /usr/bin/ccache /usr/lib/ccache/g++; \
    fi

USER builder
ENTRYPOINT ["/sbin/activatecontaineruid"]
