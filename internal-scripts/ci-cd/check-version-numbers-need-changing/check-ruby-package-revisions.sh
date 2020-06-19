#!/bin/bash
# Checks whether any Ruby package revisions need to be changed,
# as a result of changed package metadata or contents.
#
# For example, if we've modified container-entrypoints/build-ruby to
# add another file to the Ruby package, then this script will complain
# that all 'ruby.*.package_revision' fields in config.yml need to be
# bumped.
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
# Optional: MOCK_UNBUMPED_RUBY_PACKAGE_VERSIONS


HEAD_SHA_SHORT=${HEAD_SHA:0:8}

# Check whether any of the following files have changed
# in such a way that they would change the Ruby packages'
# contents or metadata.

REVIEW_GLOB='container-entrypoints/build-{jemalloc,ruby,ruby-deb,ruby-rpm}'
# shellcheck disable=SC2207,SC2012
REVIEW_FILES=($(ls container-entrypoints/build-{jemalloc,ruby,ruby-deb,ruby-rpm} | sort))


DIFF=$(git diff "$LATEST_RELEASE_TAG" "${REVIEW_FILES[@]}")
if [[ -z "$DIFF" ]]; then
    echo " * Relevant scripts did not change since $LATEST_RELEASE_TAG."
    echo "   Scripts checked: $REVIEW_GLOB"
    exit
fi

# A relevant script changed. So Ruby package revision numbers
# may need bumping.

echo " * Relevant scripts have changed compared to $LATEST_RELEASE_TAG"
echo "   Scripts checked: $REVIEW_GLOB"
echo


# Find all Ruby versions for which all of the following is true:
#
# - It's packaged by both the previous Fullstaq Ruby release
#   as well as the current one.
# - The package revision has not been bumped.
if [[ -z "$MOCK_UNBUMPED_RUBY_PACKAGE_VERSIONS" ]]; then
    git archive "$LATEST_RELEASE_TAG" config.yml | tar -xO > config-latest-release.yml
    # shellcheck disable=SC2207
    IFS=$'\n' UNBUMPED_RUBY_PACKAGE_VERSIONS=($("$SELFDIR"/determine-unbumped-ruby-package-versions.rb \
        "$ROOTDIR/config.yml" config-latest-release.yml))
else
    # shellcheck disable=SC2206
    UNBUMPED_RUBY_PACKAGE_VERSIONS=($MOCK_UNBUMPED_RUBY_PACKAGE_VERSIONS)
fi


if [[ ${#UNBUMPED_RUBY_PACKAGE_VERSIONS[@]} -eq 0 ]]; then
    echo " * All relevant Ruby package revisions have already been bumped compared to $LATEST_RELEASE_TAG."
    exit
fi


echo " * Some Ruby package revisions have not been bumped compared to $LATEST_RELEASE_TAG:"
echo
for RUBY_PACKAGE_VERSION in "${UNBUMPED_RUBY_PACKAGE_VERSIONS[@]}"; do
    echo "    - $RUBY_PACKAGE_VERSION"
done
echo
echo "------------------"
echo
echo "Checking whether manual approval is given..."

APPROVAL_DATA=$(
    echo "project=fullstaq-ruby-server-edition" &&
    echo "component=ruby-package-revisions" &&
    echo "base=$LATEST_RELEASE_TAG" &&
    sha256sum "${REVIEW_FILES[@]}"
)
APPROVAL_CHECKSUM=$(md5sum <<<"$APPROVAL_DATA" | awk '{ print $1 }')

if [[ "$MOCK_APPROVAL_STATUS" = true ]]; then
    echo "$APPROVAL_CHECKSUM" > approvals.txt
elif [[ "$MOCK_APPROVAL_STATUS" = false ]]; then
    echo -n > approvals.txt
else
    curl -fsSLO https://raw.githubusercontent.com/fullstaq-labs/fullstaq-ruby-ci-approvals/main/approvals.txt
fi

if grep -q "^${APPROVAL_CHECKSUM}$" approvals.txt; then
    echo "Manual approval detected."
else
    echo "No manual approval detected."
    echo
    echo "${BOLD}${YELLOW}*** MANUAL REVIEW AND ACTION REQUIRED ***${RESET}"
    echo
    echo "$REVIEW_GLOB has changed."
    echo "${BOLD}Please review${RESET} the changes in these files between $LATEST_RELEASE_TAG and $HEAD_SHA_SHORT:"
    echo
    echo "  ${CYAN}git diff $LATEST_RELEASE_TAG..$HEAD_SHA_SHORT $REVIEW_GLOB${RESET}"
    echo
    echo "${BOLD}${YELLOW}## How to review?${RESET}"
    echo
    echo "Check whether the code would ${BOLD}change any Ruby package contents or metadata${RESET}."
    echo
    echo "${BOLD}${YELLOW}## How to take action?${RESET}"
    echo
    echo " * If the package contents or metadata will change, then open config.yml and"
    echo "   bump the package_revision for the following Ruby packages:"
    echo
    for RUBY_PACKAGE_VERSION in "${UNBUMPED_RUBY_PACKAGE_VERSIONS[@]}"; do
        echo "    - $RUBY_PACKAGE_VERSION"
    done
    echo
    echo "  ${BOLD}-- OR --${RESET}"
    echo
    echo " * If the package contents or metadata will NOT change, then manually approve"
    echo "   by adding this line..."
    echo
    echo "     $APPROVAL_CHECKSUM"
    echo
    echo "   ...to github.com/fullstaq-labs/fullstaq-ruby-ci-approvals,"
    echo "   file approvals.txt:"
    echo
    echo "     https://github.com/fullstaq-labs/fullstaq-ruby-ci-approvals/edit/main/approvals.txt"
    echo
    echo "   You can also use this command:"
    echo
    echo "     git clone --depth=1 git@github.com:fullstaq-labs/fullstaq-ruby-ci-approvals.git &&"
    echo "     cd fullstaq-ruby-ci-approvals &&"
    echo "     echo $APPROVAL_CHECKSUM >> approvals.txt &&"
    echo "     git commit -a -m 'Approve fullstaq-ruby-server-edition ruby-package-revision $HEAD_SHA_SHORT' &&"
    echo "     git push"
    exit 1
fi
