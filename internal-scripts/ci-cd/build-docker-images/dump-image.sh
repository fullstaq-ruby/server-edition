#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar IMAGE_NAME
require_envvar IMAGE_TAG

set -x
mkdir output
docker save "$IMAGE_NAME:$IMAGE_TAG" | zstd -T0 -o output/image.tar.zst
set +x
