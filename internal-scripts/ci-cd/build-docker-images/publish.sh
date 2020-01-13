#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar IMAGE_NAME
require_envvar IMAGE_TAG

set -x
exec docker push "$IMAGE_NAME:$IMAGE_TAG"
