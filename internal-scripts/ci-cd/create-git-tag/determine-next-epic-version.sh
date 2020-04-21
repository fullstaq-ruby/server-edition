#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar LATEST_RELEASE_TAG


# shellcheck disable=SC2001
LATEST_RELEASE_VERSION=$(sed 's/^epic-//' <<<"$LATEST_RELEASE_TAG")

# shellcheck disable=SC2206
IFS=. VERSION_COMPONENTS=($LATEST_RELEASE_VERSION)

TO_BUMP=minor
# shellcheck disable=SC2207
IFS=$'\n' COMMIT_HASHES=($(git rev-list "$LATEST_RELEASE_TAG"..HEAD))

for COMMIT_HASH in "${COMMIT_HASHES[@]}"; do
    echo "Analyzing $COMMIT_HASH..."
    COMMIT_MESSAGE=$(git log --format=%B -n 1 "$COMMIT_HASH")
    if [[ "$COMMIT_MESSAGE" =~ \[major\] ]]; then
        TO_BUMP=major
        echo "  => Will bump major version"
    elif [[ "$COMMIT_MESSAGE" =~ \[minor\] ]]; then
        if [[ "$TO_BUMP" != major ]]; then
            TO_BUMP=minor
            echo "  => Will bump minor version"
        fi
    fi
done

if [[ "$TO_BUMP" = major ]]; then
    (( VERSION_COMPONENTS[0]++ )) || true
    VERSION_COMPONENTS[1]=0
else
    (( VERSION_COMPONENTS[1]++ )) || true
fi

echo
echo "::set-env name=NEXT_RELEASE_VERSION::${VERSION_COMPONENTS[0]}.${VERSION_COMPONENTS[1]}"
echo "Next epic version: ${VERSION_COMPONENTS[0]}.${VERSION_COMPONENTS[1]}"
