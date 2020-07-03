#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../.." && pwd)
# shellcheck source=../../lib/library.sh
source "$ROOTDIR/lib/library.sh"


require_envvar TARBALL

set -x
zstd -d < "$TARBALL" | docker load
