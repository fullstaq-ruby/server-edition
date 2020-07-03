#!/bin/bash
# Given an image name and tag like 'fullstaq/ruby-build-env' and '2',
# determines if that image exists on the Docker Hub. If it doesn't
# then it means the image needs to be built.
#
# Sets the following outputs:
# - needs-building: true or false.
#
# This output is used by a later step to possibly build a new
# image, with the given name and tag.
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar IMAGE_NAME
require_envvar IMAGE_TAG


function docker_tag_exists() {
    curl --silent -f -lSL "https://index.docker.io/v1/repositories/$1/tags/$2" > /dev/null
}

if docker_tag_exists "$IMAGE_NAME" "$IMAGE_TAG"; then
    echo "Docker image $IMAGE_NAME:$IMAGE_TAG already exists in the Docker Hub."
    echo "Will not build a Docker image."
    echo "::set-output name=needs-building::false"
else
    echo "Docker image $IMAGE_NAME:$IMAGE_TAG does not exist in the Docker Hub. Will build it."
    echo "::set-output name=needs-building::true"
fi
