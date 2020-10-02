#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar CI_ARTIFACTS_BUCKET
require_envvar CI_ARTIFACTS_RUN_NUMBER

URL_PREFIX="gs://$CI_ARTIFACTS_BUCKET/$CI_ARTIFACTS_RUN_NUMBER"
echo "--> Checking $URL_PREFIX/*.tar.zst"

if ENTRIES=$(gsutil ls "$URL_PREFIX/*.tar.zst" 2>stderr.txt); then
    ENTRIES=$(gsutil ls "$URL_PREFIX/*.tar.zst" | sed 's|.*/||; s|\.tar\.zst||')
    echo "$ENTRIES"
    echo "$ENTRIES" > artifacts.txt
elif grep -q "matched no objects" stderr.txt; then
    echo "(no entries)"
    echo -n > artifacts.txt
else
    cat stderr.txt >&2
    exit 1
fi
