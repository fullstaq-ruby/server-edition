#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../.." && pwd)
# shellcheck source=../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar GITHUB_RUN_NUMBER
require_envvar CI_ARTIFACTS_BUCKET
require_envvar ARTIFACT_NAME
require_envvar ARTIFACT_PATH
CI_ARTIFACTS_RUN_NUMBER=${CI_ARTIFACTS_RUN_NUMBER:-$GITHUB_RUN_NUMBER}
CLEAR=${CLEAR:-false}

URL="gs://$CI_ARTIFACTS_BUCKET/$CI_ARTIFACTS_RUN_NUMBER/$ARTIFACT_NAME.tar.zst"
if [[ "$CLEAR" = true ]]; then
    echo "--> Clearing destination directory"
    rm -rf "$ARTIFACT_PATH"
fi
echo "--> Will download from $URL"
mkdir -p "$ARTIFACT_PATH"
gsutil cp "$URL" - | zstd -d | tar -C "$ARTIFACT_PATH" -xf -

