#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../.." && pwd)
# shellcheck source=../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar GITHUB_RUN_NUMBER
require_envvar CI_ARTIFACTS_BUCKET
require_envvar ARTIFACT_NAMES
require_envvar ARTIFACT_PATH
CI_ARTIFACTS_RUN_NUMBER=${CI_ARTIFACTS_RUN_NUMBER:-$GITHUB_RUN_NUMBER}
CLEAR=${CLEAR:-false}
TMPDIR=${TMPDIR:-/tmp}

function cleanup()
{
    if [[ -n "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}

if [[ "$CLEAR" = true ]]; then
    echo "--> Clearing destination directory"
    rm -rf "$ARTIFACT_PATH"
fi

URLS=()
# shellcheck disable=SC2153
for ARTIFACT_NAME in $ARTIFACT_NAMES; do
    URL="gs://$CI_ARTIFACTS_BUCKET/$CI_ARTIFACTS_RUN_NUMBER/$ARTIFACT_NAME.tar.zst"
    URLS+=("$URL")
    echo "--> Will download from $URL"
done
echo

echo "--> Downloading artifacts"
WORK_DIR=$(mktemp -d "$TMPDIR/XXXXXX")
mkdir -p "$ARTIFACT_PATH"
gsutil cp "${URLS[@]}" "$WORK_DIR/"
echo

echo "--> Extracting artifacts"
# shellcheck disable=SC2153
for ARTIFACT_NAME in $ARTIFACT_NAMES; do
    mkdir -p "$ARTIFACT_PATH/$ARTIFACT_NAME"
    zstd -d < "$WORK_DIR/$ARTIFACT_NAME.tar.zst" | tar -C "$ARTIFACT_PATH/$ARTIFACT_NAME" -xf -
done
