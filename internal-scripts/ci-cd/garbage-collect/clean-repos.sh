#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar BINTRAY_ORG
require_envvar BINTRAY_API_USERNAME
require_envvar BINTRAY_API_KEY


function run_curl()
{
    local COMMAND

    COMMAND=(curl -sSL -o body.txt -w "%{http_code}" "$@")
    echo "+ ${COMMAND[@]}"
    "${COMMAND[@]}" > http-code.txt
    HTTP_CODE=$(cat http-code.txt)
    echo "API response: HTTP $HTTP_CODE"
    # Print body.txt while ensuring that a trailing newline is also
    # printed.
    # shellcheck disable=SC2005
    echo "$(cat body.txt)"
}

function verify_http_code_ok()
{
    if ! [[ "$HTTP_CODE" =~ ^2 ]]; then
        echo "*** ERROR: Bintray API returned non-successful HTTP code"
        exit 1
    fi
}


header "Detecting old CI repos"
OLD_CI_REPOS=$(jq -r '.[] | select(.name | test("-ci-")) | select(.lastUpdated | fromdate < now - (7 * 24 * 60 * 60)) | .name' repos.json)
echo "The following CI repos are older than a week:"
echo "$OLD_CI_REPOS"
echo


header "Deleting old CI repos"
for REPO_NAME in $OLD_CI_REPOS; do
    echo curl -u "$BINTRAY_API_USERNAME:$BINTRAY_API_KEY" -X DELETE \
        "https://bintray.com/api/v1/repos/$BINTRAY_ORG/$REPO_NAME"
done
