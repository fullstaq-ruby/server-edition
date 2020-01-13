#!/bin/bash
# Checks whether any minor Ruby package revisions need to be changed,
# as a result of packaging a different tiny Ruby version.
#
# For example, if in the last release we had this config...
#
#   minor_version_packages:
#     - minor_version: 2.7
#       full_version: 2.7.0
#       package_revision: 0
#
# ...and now we have this...
#
#   minor_version_packages:
#     - minor_version: 2.7
#       full_version: 2.7.1   # <---- !!!!
#       package_revision: 0
#
# ...then this script will complain that 'package_revision' also needs
# to be bumped.
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar LATEST_RELEASE_TAG

# The following optional variables are for testing purposes.
HEAD_SHA=${HEAD_SHA:-$(git rev-parse HEAD)}
MOCK_APPROVAL_STATUS=${MOCK_APPROVAL_STATUS:-not set} # may be set to true or false


HEAD_SHA_SHORT=${HEAD_SHA:0:8}


git archive "$LATEST_RELEASE_TAG" config.yml | tar -xO > config-latest-release.yml
# Find all minor Ruby versions for which all of the following is true:
#
# - It's packaged by both the previous Fullstaq Ruby release
#   as well as the current one.
# - Its `full_version` has changed compared to the previous release.
# - The package revision has not been bumped.
#
# shellcheck disable=SC2207
IFS=$'\n' UNBUMPED_MINOR_RUBY_PACKAGE_VERSIONS=($("$SELFDIR"/determine-unbumped-minor-ruby-package-versions.rb \
    "$ROOTDIR/config.yml" config-latest-release.yml))


if [[ ${#UNBUMPED_MINOR_RUBY_PACKAGE_VERSIONS[@]} -eq 0 ]]; then
    echo "All relevant Ruby minor package revisions have already been bumped compared to $LATEST_RELEASE_TAG."
else
    echo "In config.yml, please bump the following ${BOLD}ruby.minor_version_packages.package_revision${RESET}s:"
    echo
    for MINOR_RUBY_PACKAGE_VERSION in "${UNBUMPED_MINOR_RUBY_PACKAGE_VERSIONS[@]}"; do
        echo " * $MINOR_RUBY_PACKAGE_VERSION"
    done
fi
