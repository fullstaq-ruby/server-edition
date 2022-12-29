FROM ubuntu:18.04

# Used to link container image to the repo:
# https://docs.github.com/en/free-pro-team@latest/packages/managing-container-images-with-github-container-registry/connecting-a-repository-to-a-container-image#connecting-a-repository-to-a-container-image-on-the-command-line
LABEL org.opencontainers.image.source https://github.com/fullstaq-ruby/server-edition

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

COPY Gemfile Gemfile.lock /utility_build/

RUN set -x && \
    apt update && \
    apt install -y wget ca-certificates binutils build-essential \
        curl ca-certificates rpm file ruby ruby-dev rubygems sudo \
        aptly createrepo parallel && \
    apt clean && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

RUN set -x && \
    curl -fsSLo /sbin/matchhostfsowner.gz https://github.com/FooBarWidget/matchhostfsowner/releases/download/v0.9.8/matchhostfsowner-0.9.8-x86_64-linux.gz && \
    gunzip /sbin/matchhostfsowner.gz && \
    chmod +x,+s /sbin/matchhostfsowner && \
    mkdir /etc/matchhostfsowner && \
    echo 'app_account: utility' > /etc/matchhostfsowner/config.yml && \
    addgroup --gid 9999 utility && \
    adduser --uid 9999 --gid 9999 --disabled-password --gecos Utility utility && \
    usermod -L utility

RUN set -x && \
    gem install bundler --no-document -v 2.2.28 && \
    mkdir /bundle && \
    chown utility: /bundle && \
    cp /utility_build/* /home/utility/ && \
    cd /home/utility && \
    sudo -H -u utility bundle config set --local path /bundle && \
    sudo -H -u utility bundle install -j4 && \
    rm -rf /utility_build /tmp/* /var/tmp/*

USER utility
ENTRYPOINT ["/sbin/matchhostfsowner"]
