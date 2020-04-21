#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar BINTRAY_ORG
require_envvar BINTRAY_API_USERNAME
require_envvar BINTRAY_API_KEY
require_envvar REPO_NAME


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


run_curl -u "$BINTRAY_API_USERNAME:$BINTRAY_API_KEY" -X POST \
    -H 'Content-Type: application/json' \
    -d '{ "publish_wait_for_secs": -1 }' \
    "https://bintray.com/api/v1/content/$BINTRAY_ORG/$REPO_NAME/fullstaq-ruby/all/publish"
verify_http_code_ok
