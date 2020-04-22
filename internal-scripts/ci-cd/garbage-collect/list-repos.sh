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

    COMMAND=(curl -sSL -w "%{http_code}" "$@")
    echo "+ ${COMMAND[@]}"
    "${COMMAND[@]}" > http-code.txt
    HTTP_CODE=$(cat http-code.txt)
    echo "API response: HTTP $HTTP_CODE"
}

function verify_http_code_ok()
{
    if ! [[ "$HTTP_CODE" =~ ^2 ]]; then
        echo "*** ERROR: Bintray API returned non-successful HTTP code"
        exit 1
    fi
}


run_curl -u "$BINTRAY_API_USERNAME:$BINTRAY_API_KEY" -o repos.json \
    "https://bintray.com/api/v1/repos/$BINTRAY_ORG"
verify_http_code_ok
run jq -C . repos.json
