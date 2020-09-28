#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar BINTRAY_API_USERNAME
require_envvar BINTRAY_API_KEY
require_envvar BINTRAY_ORG
require_envvar REPO_NAME
require_envvar REPO_PACKAGE_VERSION
require_envvar DRY_RUN
require_envvar IGNORE_EXISTING


echo "$BINTRAY_API_KEY" > bintray-api-key.txt

ARGS=()
if $DRY_RUN; then
    ARGS+=(-R)
fi
if $IGNORE_EXISTING; then
    ARGS+=(-i)
fi

set +x
exec ./upload-debs \
    -u "$BINTRAY_API_USERNAME" \
    -k bintray-api-key.txt \
    -j 16 \
    -O "$BINTRAY_ORG" \
    -n "$REPO_NAME" \
    -v "$REPO_PACKAGE_VERSION" \
    "${ARGS[@]}" "$@"
