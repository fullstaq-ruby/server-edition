#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar PACKAGE_BASENAME
require_envvar VERSION
require_envvar REVISION


set -x
mkdir output
exec "$ROOTDIR/build-common-rpm" \
    -o "output/$PACKAGE_BASENAME" \
    -v "$VERSION" \
    -r "$REVISION"
