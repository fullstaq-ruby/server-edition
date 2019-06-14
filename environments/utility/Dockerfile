FROM ubuntu:18.04

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

COPY Gemfile Gemfile.lock /utility_build/

RUN set -x && \
    apt update && \
    apt install -y wget ca-certificates binutils build-essential \
        curl ca-certificates rpm file ruby ruby-dev rubygems sudo \
        aptly createrepo && \
    \
    curl -sSLo /sbin/activatecontaineruid.gz https://github.com/fullstaq-labs/activatecontaineruid/releases/download/v0.9.1/activatecontaineruid-0.9.1-x86_64-linux.gz && \
    gunzip /sbin/activatecontaineruid.gz && \
    chmod +x,+s /sbin/activatecontaineruid && \
    mkdir /etc/activatecontaineruid && \
    echo 'app_account: utility' > /etc/activatecontaineruid/config.yml && \
    \
    gem install bundler --no-document -v 1.17.3 && \
    addgroup --gid 9999 utility && \
    adduser --uid 9999 --gid 9999 --disabled-password --gecos Utility utility && \
    usermod -L utility && \
    mkdir /bundle && \
    chown utility: /bundle && \
    cp /utility_build/* /home/utility/ && \
    cd /home/utility && \
    sudo -H -u utility bundle install -j4 --path /bundle && \
    apt clean && \
    rm -rf /utility_build /tmp/* /var/tmp/* /var/lib/apt/lists/*

USER utility
ENTRYPOINT ["/sbin/activatecontaineruid"]
