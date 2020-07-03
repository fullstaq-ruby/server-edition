#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar DISTRIBUTION_NAME
require_envvar VARIANT_NAME
require_envvar PACKAGE_FORMAT
require_envvar RUBY_PACKAGE_VERSION_ID
require_envvar RUBY_PACKAGE_REVISION
# Optional envvar: VARIANT_PACKAGE_SUFFIX


UTILITY_IMAGE_NAME=fullstaq/ruby-build-env-utility
UTILITY_IMAGE_TAG=$(read_single_value_file "$ROOTDIR/environments/utility/image_tag")

mkdir output

if [[ "$PACKAGE_FORMAT" = DEB ]]; then
    PACKAGE_BASENAME=fullstaq-ruby-${RUBY_PACKAGE_VERSION_ID}${VARIANT_PACKAGE_SUFFIX}_${RUBY_PACKAGE_REVISION}-${DISTRIBUTION_NAME}_amd64.deb
    touch "output/$PACKAGE_BASENAME"

    exec docker run --rm --init \
        -v "$ROOTDIR:/system:ro" \
        -v "$(pwd)/ruby-bin.tar.gz:/input/ruby-bin.tar.gz:ro" \
        -v "$(pwd)/output/$PACKAGE_BASENAME:/output/ruby.deb" \
        -e "REVISION=$RUBY_PACKAGE_REVISION" \
        --user "$(id -u):$(id -g)" \
        "$UTILITY_IMAGE_NAME:$UTILITY_IMAGE_TAG" \
        /system/container-entrypoints/build-ruby-deb
else
    DISTRO_SUFFIX=$(sed 's/-//g' <<<"$DISTRIBUTION_NAME")
    PACKAGE_BASENAME=fullstaq-ruby-${RUBY_PACKAGE_VERSION_ID}${VARIANT_PACKAGE_SUFFIX}-rev${RUBY_PACKAGE_REVISION}-${DISTRO_SUFFIX}.x86_64.rpm
    touch "output/$PACKAGE_BASENAME"

    exec docker run --rm --init \
        -v "$ROOTDIR:/system:ro" \
        -v "$(pwd)/ruby-bin.tar.gz:/input/ruby-bin.tar.gz:ro" \
        -v "$(pwd)/output/$PACKAGE_BASENAME:/output/ruby.rpm" \
        -e "REVISION=$RUBY_PACKAGE_REVISION" \
        --user "$(id -u):$(id -g)" \
        "$UTILITY_IMAGE_NAME:$UTILITY_IMAGE_TAG" \
        /system/container-entrypoints/build-ruby-rpm
fi
