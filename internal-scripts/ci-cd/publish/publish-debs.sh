#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar UTILITY_IMAGE_NAME
require_envvar UTILITY_IMAGE_TAG
require_envvar BINTRAY_API_USERNAME
require_envvar BINTRAY_API_KEY
require_envvar REPO_NAME
require_envvar DRY_RUN
require_envvar IGNORE_EXISTING


echo "$BINTRAY_API_KEY" > bintray-api-key.txt

MOUNT_ARGS=()
for F in "$@"; do
    ABS_PATH=$(absolute_path "$F")
    MOUNT_ARGS+=(-v "$ABS_PATH:/input/$ABS_PATH:ro")
done

exec docker run --rm --init \
    -v "$ROOTDIR:/system:ro" \
    -v "$(pwd)/bintray-api-key.txt:/bintray_api_key.txt:ro" \
    "${MOUNT_ARGS[@]}" \
    -e "API_USERNAME=$BINTRAY_API_USERNAME" \
    -e "CONCURRENCY=16" \
    -e "DRY_RUN=$DRY_RUN" \
    -e "REPO_NAME=$REPO_NAME" \
    -e "REPUBLISH=false" \
    -e "IGNORE_EXISTING=$IGNORE_EXISTING" \
    --user "$(id -u):$(id -g)" \
    "$UTILITY_IMAGE_NAME:$UTILITY_IMAGE_TAG" \
    /system/container-entrypoints/upload-debs
