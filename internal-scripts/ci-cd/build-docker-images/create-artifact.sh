#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar IMAGE_NAME
require_envvar IMAGE_TAG

set -x
mkdir output
echo "$IMAGE_NAME" > output/image_name.txt
echo "$IMAGE_TAG" > output/image_tag.txt
set +x
