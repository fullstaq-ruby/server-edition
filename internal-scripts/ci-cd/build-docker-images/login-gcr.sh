#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


run gcloud auth activate-service-account --key-file <(base64 -d <<< "$SERVICE_ACCOUNT_KEY_JSON")
run gcloud auth configure-docker gcr.io
