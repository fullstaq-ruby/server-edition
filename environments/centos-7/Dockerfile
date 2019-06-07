FROM centos:7

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

RUN set -x && \
    yum install -y epel-release && \
    yum install -y --enablerepo epel \
        gcc bzip2 openssl-devel libyaml-devel libffi-devel readline-devel \
        zlib-devel gdbm-devel ncurses-devel ccache && \
    groupadd --gid 9999 builder && \
    adduser --uid 9999 --gid 9999 --password '#' app && \
    yum clean all && \
    if ! test -e /usr/lib/ccache/cc; then \
        mkdir -p /usr/lib/ccache && \
        ln -s /usr/bin/ccache /usr/lib/ccache/cc && \
        ln -s /usr/bin/ccache /usr/lib/ccache/gcc && \
        ln -s /usr/bin/ccache /usr/lib/ccache/c++ && \
        ln -s /usr/bin/ccache /usr/lib/ccache/g++ && \
    fi
