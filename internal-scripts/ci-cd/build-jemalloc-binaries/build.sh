#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar ENVIRONMENT_NAME
require_envvar CACHE_CONTAINER
require_envvar CACHE_KEY_PREFIX


set -x
mkdir output
exec "$ROOTDIR/build-jemalloc" \
    -n "$ENVIRONMENT_NAME" \
    -s "$(pwd)/cache/jemalloc-src.tar.bz2" \
    -o "$(pwd)/output/jemalloc-bin.tar.gz" \
    -j $(nproc) \
    -c azure-connection-string.txt \
    -r "$CACHE_CONTAINER" \
    -d "$CACHE_KEY_PREFIX"
