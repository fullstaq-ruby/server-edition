#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar BUILD_IMAGE_NAME
require_envvar BUILD_IMAGE_TAG
require_envvar ENVIRONMENT_NAME


mkdir output
touch output/jemalloc-bin.tar.gz

exec docker run --rm --init \
    -v "$ROOTDIR:/system:ro" \
    -v "$(pwd)/cache/jemalloc-src.tar.bz2:/input/jemalloc-src.tar.bz2:ro" \
    -v "$(pwd)/output/jemalloc-bin.tar.gz:/output/jemalloc-bin.tar.gz" \
    -v "$(pwd)/cache:/cache:delegated" \
    -e "ENVIRONMENT_NAME=$ENVIRONMENT_NAME" \
    -e "BUILD_CONCURRENCY=2" \
    --user "$(id -u):$(id -g)" \
    "$BUILD_IMAGE_NAME:$BUILD_IMAGE_TAG" \
    /system/container-entrypoints/build-jemalloc
