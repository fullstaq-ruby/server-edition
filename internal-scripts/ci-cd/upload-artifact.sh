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

URL="gs://$CI_ARTIFACTS_BUCKET/$CI_ARTIFACTS_RUN_NUMBER/$ARTIFACT_NAME.tar.zst"
echo "--> Will upload to $URL"
if ! tar -C "$ARTIFACT_PATH" -cf - . | zstd -T0 | gsutil cp - "$URL"; then
    echo "--> Artifact upload failed; cleaning up"
    gsutil rm "$URL" || true
    exit 1
fi
