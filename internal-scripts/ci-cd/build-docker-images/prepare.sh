#!/bin/bash
# Given an image name and tag like 'fullstaq/ruby-build-env' and '2',
# determines if that image exists on the Docker Hub.
#
# Sets the following outputs:
# - needs-building: true or false.
# - image-name
# - image-tag
#
# These outputs are used by a later step to possibly build a new
# image, with the given name and tag.
#
# If the image+tag already exists on the Docker Hub, or if the CI is running
# on the master branch, then the 'image-name' and 'image-tag' outputs are set to
# the original image name and tag.
#
# Otherwise, they are set to a new name+tag.
# - The new image name indicates that the image is to be stored on Google
#   Container Registry (GCR). We use GCR for storing temporary images
#   built by the CI system.
# - The new tag is unique, and contains a timestamp so that a garbage
#   collection workflow can clean up such temporary images later.
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar IMAGE_NAME
require_envvar IMAGE_TAG
require_envvar IMAGE_ID
require_envvar CI_REF
require_envvar CI_RUN_NUMBER


function docker_tag_exists() {
    curl --silent -f -lSL "https://index.docker.io/v1/repositories/$1/tags/$2" > /dev/null
}

if docker_tag_exists "$IMAGE_NAME" "$IMAGE_TAG"; then
    echo "Docker image $IMAGE_NAME:$IMAGE_TAG already exists in the Docker Hub."
    echo "Will not build a Docker image."
    echo "::set-output name=needs-building::false"
    echo "::set-output name=image-name::$IMAGE_NAME"
    echo "::set-output name=image-tag::$IMAGE_TAG"
    exit
fi

echo "Docker image $IMAGE_NAME:$IMAGE_TAG does not exist in the Docker Hub."

if [[ "$CI_REF" = refs/heads/master ]]; then
    echo "CI system is running on master branch."
    echo "Will build a Docker image using this name and tag: $IMAGE_NAME:$IMAGE_TAG"
    echo "::set-output name=needs-building::true"
    echo "::set-output name=image-name::$IMAGE_NAME"
    echo "::set-output name=image-tag::$IMAGE_TAG"
    exit
fi

TIMESTAMP=$(date +%s)
RESULT_IMAGE_TAG="dev-${TIMESTAMP}-${CI_RUN_NUMBER}"
echo "Will build a Docker image using this tag: $RESULT_IMAGE_TAG"
echo "::set-output name=needs-building::true"
echo "::set-output name=image-name::gcr.io/fullstaq-ruby/fullstaq-ruby-build-env-$IMAGE_ID"
echo "::set-output name=image-tag::$RESULT_IMAGE_TAG"
