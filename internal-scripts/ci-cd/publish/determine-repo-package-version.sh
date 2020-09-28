#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar LATEST_RELEASE_TAG


HEAD_SHA=$(git rev-parse HEAD)
HEAD_SHA_SHORT=${HEAD_SHA:0:8}
REPO_PACKAGE_VERSION="${LATEST_RELEASE_TAG}_${HEAD_SHA_SHORT}"

echo "::set-env name=REPO_PACKAGE_VERSION::$REPO_PACKAGE_VERSION"
echo "Result: $REPO_PACKAGE_VERSION"
