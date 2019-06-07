FROM ubuntu:18.04

# If you make a change and you want to force users to re-pull the image
# (e.g. when your change adds a feature that our scripts rely on, or is
# breaking), then bump the version number in the `image_tag` file.

COPY Gemfile Gemfile.lock /utility_build/

RUN set -x && \
    apt update && \
    apt install -y wget ca-certificates binutils dpkg-dev \
        ruby rubygems sudo && \
    gem install bundler --no-document -v 2.0.1 \
    addgroup --gid 9999 utility && \
    adduser --uid 9999 --gid 9999 --disabled-password --gecos Builder utility && \
    usermod -L utility && \
    cd /utility_build && \
    sudo -u utility bundle install -j4 && \
    cd / &&
    apt clean && \
    rm -rf /utility_build /tmp/* /var/tmp/* /var/lib/apt/lists/*
