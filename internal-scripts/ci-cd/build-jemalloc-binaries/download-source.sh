#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar JEMALLOC_VERSION


if [[ -e cache/jemalloc-src.tar.bz2 ]]; then
    echo "Source fetched from cache, no need to download."
else
    run wget --output-document=cache/jemalloc-src.tar.bz2 "https://github.com/jemalloc/jemalloc/releases/download/$JEMALLOC_VERSION/jemalloc-$JEMALLOC_VERSION.tar.bz2"
fi
