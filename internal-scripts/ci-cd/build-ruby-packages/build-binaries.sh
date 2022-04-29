#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar ENVIRONMENT_NAME
require_envvar VARIANT_NAME
require_envvar RUBY_PACKAGE_VERSION_ID
require_envvar CACHE_CONTAINER
require_envvar CACHE_KEY_PREFIX


if [[ "$VARIANT_NAME" = jemalloc ]]; then
    VARIANT_ARGS=(-m "$(pwd)/jemalloc-bin.tar.gz")
elif [[ "$VARIANT_NAME" = malloctrim ]]; then
    VARIANT_ARGS=(-t)
else
    VARIANT_ARGS=()
fi

set -x
exec "$ROOTDIR/build-ruby" \
    -n "$ENVIRONMENT_NAME" \
    -s "$(pwd)/ruby-src.tar.gz" \
    -v "$RUBY_PACKAGE_VERSION_ID" \
    -o "$(pwd)/ruby-bin-$VARIANT_NAME.tar.gz" \
    "${VARIANT_ARGS[@]}" \
    -j 2 \
    -c azure-connection-string.txt \
    -r "$CACHE_CONTAINER" \
    -d "$CACHE_KEY_PREFIX"
