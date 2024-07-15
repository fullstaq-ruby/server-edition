#!/usr/bin/env bash
set -e

echo "### Free disk space before cleaning:"
df -h

# Based on https://stackoverflow.com/questions/75536771/github-runner-out-of-disk-space-after-building-docker-image
echo
echo "### Cleaning...."
sudo rm -rf "$AGENT_TOOLSDIRECTORY" /usr/share/dotnet /usr/local/lib/android /opt/ghc \
    /usr/local/share/powershell /usr/share/swift /usr/local/.ghcup /usr/lib/jvm
sudo apt purge -y aria2 shellcheck zsync google-chrome-stable \
    ant ant-optional kubectl mercurial apt-transport-https yarn libssl-dev \
    libfreetype6-dev libfontconfig1 snmp pollinate libpq-dev sphinxsearch
sudo apt purge -y '^mysql'
sudo apt purge -y '^php'
sudo apt purge -y '^dotnet'
sudo apt autoremove -y
sudo apt autoclean -y

echo
echo "### Free disk space after cleaning:"
df -h
