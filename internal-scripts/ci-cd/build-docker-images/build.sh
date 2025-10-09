#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar IMAGE_NAME
require_envvar IMAGE_TAG
require_envvar SOURCE_DIR

# Optional: ARCH (amd64|arm64). Defaults to host arch (treated as amd64 for now)
ARCH=${ARCH:-amd64}
case "$ARCH" in
	amd64|arm64) ;;
	*) echo "ERROR: Unsupported ARCH=$ARCH" >&2; exit 1 ;;
esac

PLATFORM="linux/$ARCH"

set -x
# Use buildx to allow cross-building for arm64 on amd64 runners
docker buildx create --name fsruby_builder --use 2>/dev/null || docker buildx use fsruby_builder
exec docker buildx build --pull --platform "$PLATFORM" --load -t "$IMAGE_NAME:$IMAGE_TAG" "$SOURCE_DIR"
