#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar GITHUB_ENV


run git fetch

echo "+ Calculating..."

MERGE_BASE=$(git merge-base origin/main HEAD)
LATEST_RELEASE_TAG=$(git describe "$MERGE_BASE" --tags --abbrev=0 --match='epic-*')

echo "LATEST_RELEASE_TAG=$LATEST_RELEASE_TAG" >> "$GITHUB_ENV"
echo "Latest release tag: $LATEST_RELEASE_TAG"
