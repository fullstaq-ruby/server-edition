#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"
# shellcheck source=create-repo-package.sh
source "$SELFDIR/create-repo-package.sh"

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


header "Deleting repo"
run_curl -u "$BINTRAY_API_USERNAME:$BINTRAY_API_KEY" -X DELETE \
    "https://bintray.com/api/v1/repos/$BINTRAY_ORG/$REPO_NAME"
if ! [[ "$HTTP_CODE" =~ ^2 ]] && [[ "$HTTP_CODE" != 404 ]]; then
    echo "*** ERROR: Bintray API returned non-successful HTTP code"
    exit 1
fi
echo


header "Creating repo"
run_curl -u "$BINTRAY_API_USERNAME:$BINTRAY_API_KEY" -X POST \
    -H 'Content-Type: application/json' -d '{ "type": "rpm", "yum_metadata_depth": 2 }' \
    "https://bintray.com/api/v1/repos/$BINTRAY_ORG/$REPO_NAME"
verify_http_code_ok
echo


create_package
