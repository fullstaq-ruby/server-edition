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
# Optional envvar: ARCH (defaults to amd64)

ARCH=${ARCH:-amd64}

function deb_arch_for() {
    case "$1" in
        amd64) echo amd64 ;;
        arm64|aarch64) echo arm64 ;;
        *) echo "$1" ;;
    esac
}

function rpm_arch_for() {
    case "$1" in
        amd64) echo x86_64 ;;
        arm64|aarch64) echo aarch64 ;;
        *) echo "$1" ;;
    esac
}


mkdir "output-$VARIANT_NAME"

if [[ "$PACKAGE_FORMAT" = DEB ]]; then
    PACKAGE_BASENAME=fullstaq-ruby-${RUBY_PACKAGE_VERSION_ID}${VARIANT_PACKAGE_SUFFIX}_${RUBY_PACKAGE_REVISION}-${DISTRIBUTION_NAME}_$(deb_arch_for "$ARCH").deb
    set -x
    exec "$ROOTDIR/build-ruby-deb" \
        -b "ruby-bin-$VARIANT_NAME.tar.gz" \
        -o "output-$VARIANT_NAME/$PACKAGE_BASENAME" \
        -r "$RUBY_PACKAGE_REVISION"
else
    # shellcheck disable=SC2001
    DISTRO_SUFFIX=$(sed 's/-//g' <<<"$DISTRIBUTION_NAME")
    PACKAGE_BASENAME=fullstaq-ruby-${RUBY_PACKAGE_VERSION_ID}${VARIANT_PACKAGE_SUFFIX}-rev${RUBY_PACKAGE_REVISION}-${DISTRO_SUFFIX}.$(rpm_arch_for "$ARCH").rpm
    set -x
    exec "$ROOTDIR/build-ruby-rpm" \
        -b "ruby-bin-$VARIANT_NAME.tar.gz" \
        -o "output-$VARIANT_NAME/$PACKAGE_BASENAME" \
        -r "$RUBY_PACKAGE_REVISION"
fi
