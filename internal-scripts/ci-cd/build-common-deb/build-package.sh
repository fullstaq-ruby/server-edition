#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar UTILITY_IMAGE_NAME
require_envvar UTILITY_IMAGE_TAG
require_envvar PACKAGE_BASENAME
require_envvar VERSION
require_envvar REVISION


mkdir output
touch output/"$PACKAGE_BASENAME"

exec docker run --rm --init \
  -v "$ROOTDIR:/system:ro" \
  -v "$(pwd)/output/$PACKAGE_BASENAME:/output/common.deb" \
  -e "VERSION=$VERSION" \
  -e "REVISION=$REVISION" \
  --user "$(id -u):$(id -g)" \
  "$UTILITY_IMAGE_NAME:$UTILITY_IMAGE_TAG" \
  /system/container-entrypoints/build-common-deb
