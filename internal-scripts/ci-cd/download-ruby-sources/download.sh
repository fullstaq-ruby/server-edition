#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar RUBY_VERSION


MINOR_VERSION=$(sed -E 's/(.+)\..*/\1/' <<<"$RUBY_VERSION")

if [[ -e output/ruby-src.tar.gz ]]; then
    echo "Source fetched from cache, no need to download."
else
    run mkdir output
    run wget --output-document output/ruby-src.tar.gz \
        "https://cache.ruby-lang.org/pub/ruby/$MINOR_VERSION/ruby-$RUBY_VERSION.tar.gz"
fi
