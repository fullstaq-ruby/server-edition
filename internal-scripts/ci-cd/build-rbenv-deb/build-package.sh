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
mkdir rbenv
tar -C rbenv -xzf rbenv-src.tar.gz
mkdir output
exec "$ROOTDIR/build-rbenv-deb" \
    -s rbenv \
    -o "output/$PACKAGE_BASENAME" \
    -n "$VERSION" \
    -r "$REVISION"
