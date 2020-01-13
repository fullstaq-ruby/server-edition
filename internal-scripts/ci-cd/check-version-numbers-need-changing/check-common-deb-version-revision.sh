#!/bin/bash
# Checks whether the fullstaq-ruby-common Debian package
# version or revision needs to be changed.
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

# Check whether any of the following files have changed
# in such a way that they would change the fullstaq-ruby-common
# Debian package's contents or metadata.

REVIEW_GLOB="container-entrypoints/build-common-deb"
# shellcheck disable=SC2207,SC2012
REVIEW_FILES=($(ls container-entrypoints/build-common-deb | sort))


DIFF=$(git diff "$LATEST_RELEASE_TAG" "${REVIEW_FILES[@]}")
if [[ -z "$DIFF" ]]; then
    echo " * Relevant scripts did not change since $LATEST_RELEASE_TAG."
    echo "   Scripts checked: $REVIEW_GLOB"
    exit
fi

# A relevant script changed. So `common.deb.(version|package_revision)`
# may need bumping.

echo " * Relevant scripts have changed compared to $LATEST_RELEASE_TAG"
echo "   Scripts checked: $REVIEW_GLOB"
echo


CURRENT_COMMON_PACKAGE_VERSION=$(ruby -ryaml -e 'puts YAML.load_file("config.yml")["common"]["deb"]["version"]')
CURRENT_COMMON_PACKAGE_REVISION=$(ruby -ryaml -e 'puts YAML.load_file("config.yml")["common"]["deb"]["package_revision"]')
LATEST_RELEASE_COMMON_PACKAGE_VERSION=$(git archive "$LATEST_RELEASE_TAG" config.yml | tar -xO | ruby -ryaml -e 'puts YAML.load(STDIN)["common"]["deb"]["version"]')
LATEST_RELEASE_COMMON_PACKAGE_REVISION=$(git archive "$LATEST_RELEASE_TAG" config.yml | tar -xO | ruby -ryaml -e 'puts YAML.load(STDIN)["common"]["deb"]["package_revision"]')

if [[ "$CURRENT_COMMON_PACKAGE_VERSION" != "$LATEST_RELEASE_COMMON_PACKAGE_VERSION" ]]; then
    echo " * The fullstaq-ruby-common Debian package version has been changed compared to $LATEST_RELEASE_TAG."
    echo
    echo "       Was: $LATEST_RELEASE_COMMON_PACKAGE_VERSION"
    echo "    Is now: $CURRENT_COMMON_PACKAGE_VERSION"
    echo

    if [[ "$CURRENT_COMMON_PACKAGE_REVISION" = 0 ]]; then
        echo " * The fullstaq-ruby-common Debian package revision is properly set to 0."
        exit
    else
        echo " * The fullstaq-ruby-common Debian package revision is not set to 0."
        echo
        echo "${BOLD}${YELLOW}*** ACTION REQUIRED ***${RESET}"
        echo "Please edit config.yml and change ${BOLD}common.deb.package_revision${RESET} to 0."
        exit 1
    fi
fi
if [[ "$CURRENT_COMMON_PACKAGE_REVISION" -gt "$LATEST_RELEASE_COMMON_PACKAGE_REVISION" ]]; then
    echo " * The fullstaq-ruby-common Debian package revision has been bumped compared"
    echo "   to $LATEST_RELEASE_TAG."
    echo
    echo "       Was: $LATEST_RELEASE_COMMON_PACKAGE_REVISION"
    echo "    Is now: $CURRENT_COMMON_PACKAGE_REVISION"
    exit
fi


echo " * Neither the fullstaq-ruby-common Debian package version nor its revision has"
echo "   been bumped compared to $LATEST_RELEASE_TAG."
echo
echo "   Version: $LATEST_RELEASE_COMMON_PACKAGE_VERSION"
echo "   Revision: $LATEST_RELEASE_COMMON_PACKAGE_REVISION"
echo
echo "------------------"
echo
echo "Checking whether manual approval is given..."

APPROVAL_DATA=$(
    echo "project=fullstaq-ruby-server-edition" &&
    echo "component=common-deb-version-revision" &&
    echo "base=$LATEST_RELEASE_TAG" &&
    sha256sum "${REVIEW_FILES[@]}"
)
APPROVAL_CHECKSUM=$(md5sum <<<"$APPROVAL_DATA" | awk '{ print $1 }')

if [[ "$MOCK_APPROVAL_STATUS" = true ]]; then
    echo "$APPROVAL_CHECKSUM" > approvals.txt
elif [[ "$MOCK_APPROVAL_STATUS" = false ]]; then
    echo -n > approvals.txt
else
    curl -fsSLO https://raw.githubusercontent.com/fullstaq-labs/fullstaq-ruby-ci-approvals/master/approvals.txt
fi

if grep -q "^${APPROVAL_CHECKSUM}$" approvals.txt; then
    echo "Manual approval detected."
else
    echo "No manual approval detected."
    echo
    echo "${BOLD}${YELLOW}*** MANUAL REVIEW AND ACTION REQUIRED ***${RESET}"
    echo
    echo "$REVIEW_GLOB has changed. ${BOLD}Please review${RESET} the changes"
    echo "in these files between $LATEST_RELEASE_TAG and $HEAD_SHA_SHORT:"
    echo
    echo "  ${CYAN}git diff $LATEST_RELEASE_TAG..$HEAD_SHA_SHORT $REVIEW_GLOB${RESET}"
    echo
    echo "${BOLD}${YELLOW}## How to review?${RESET}"
    echo
    echo "Check whether the code would ${BOLD}change the fullstaq-ruby-common Debian"
    echo "package contents or metadata${RESET}."
    echo
    echo "${BOLD}${YELLOW}## How to take action?${RESET}"
    echo
    echo " * If the package contents or metadata will change, then edit"
    echo "   config.yml and bump either common.deb.version or"
    echo "   common.deb.package_revision."
    echo
    echo "  ${BOLD}-- OR --${RESET}"
    echo
    echo " * If the package contents or metadata will NOT change, then"
    echo "   manually approve by adding this line..."
    echo
    echo "     $APPROVAL_CHECKSUM"
    echo
    echo "   ...to github.com/fullstaq-labs/fullstaq-ruby-ci-approvals,"
    echo "   file approvals.txt:"
    echo
    echo "     https://github.com/fullstaq-labs/fullstaq-ruby-ci-approvals/edit/master/approvals.txt"
    echo
    echo "   You can also use this command:"
    echo
    echo "     git clone --depth=1 git@github.com:fullstaq-labs/fullstaq-ruby-ci-approvals.git &&"
    echo "     cd fullstaq-ruby-ci-approvals &&"
    echo "     echo $APPROVAL_CHECKSUM >> approvals.txt &&"
    echo "     git commit -a -m 'Approve fullstaq-ruby-server-edition common-deb-version-revision $HEAD_SHA_SHORT' &&"
    echo "     git push"
    exit 1
fi
