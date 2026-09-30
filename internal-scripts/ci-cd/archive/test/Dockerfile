# Test environment for the archive scripts. Mirrors the CI publish job:
# Aptly comes from the Aptly repo (like install-aptly.sh), createrepo_c
# and GPG from Ubuntu. gsutil, az and docker are replaced by the fakes
# in fake-bin/.
FROM ubuntu:22.04

RUN set -x && \
    apt update && \
    apt install -y ca-certificates curl gpg ruby createrepo-c rpm \
        bzip2 xz-utils zstd && \
    echo 'deb http://repo.aptly.info/ squeeze main' > /etc/apt/sources.list.d/aptly.list && \
    curl -fsSL https://www.aptly.info/pubkey.txt | gpg --dearmor -o /etc/apt/trusted.gpg.d/aptly.gpg && \
    apt update && \
    apt install -y aptly && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
