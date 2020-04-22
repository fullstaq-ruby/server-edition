#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar DISTRIBUTION_NAME
require_envvar RUBY_PACKAGE_ID
require_envvar PACKAGE_FORMAT
require_envvar VARIANT_NAME
require_envvar TEST_IMAGE_NAME
require_envvar APT_REPO_URL
require_envvar YUM_REPO_URL
# Optional envvar: VARIANT_PACKAGE_SUFFIX


mkdir repo
echo '--- Entering main Docker container ---'

if [[ "$PACKAGE_FORMAT" == DEB ]]; then
    set -x
    exec docker run --rm --init \
        -v "$ROOTDIR:/system:ro" \
        -v "$(pwd)/repo:/input/repo:ro" \
        -e "SERVER=$APT_REPO_URL" \
        -e "APT_DISTRO_NAME=$DISTRIBUTION_NAME" \
        -e "RUBY_PACKAGE_VERSION=$RUBY_PACKAGE_ID$VARIANT_PACKAGE_SUFFIX" \
        -e "EXPECTED_VARIANT=$VARIANT_NAME" \
        -e "DEBUG_AFTER_TESTS=false" \
        --user root \
        --entrypoint /system/container-entrypoints/test-debs \
        "$TEST_IMAGE_NAME"
else
    set -x
    exec docker run --rm --init \
        -v "$ROOTDIR:/system:ro" \
        -v "$(pwd)/repo:/input/repo:ro" \
        -e "SERVER=$YUM_REPO_URL/$DISTRIBUTION_NAME" \
        -e "RUBY_PACKAGE_VERSION=$RUBY_PACKAGE_ID$VARIANT_PACKAGE_SUFFIX" \
        -e "EXPECTED_VARIANT=$VARIANT_NAME" \
        -e "DEBUG_AFTER_TESTS=false" \
        --user root \
        --entrypoint /system/container-entrypoints/test-rpms \
        "$TEST_IMAGE_NAME"
fi
