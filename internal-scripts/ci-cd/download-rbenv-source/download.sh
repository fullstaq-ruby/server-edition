#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

require_envvar RBENV_REPO_URL
require_envvar RBENV_REPO_REF


if [[ -e output/rbenv-src.tar.gz ]]; then
    echo "Source fetched from cache, no need to download."
    exit
fi

mkdir output

set -x
git clone "$RBENV_REPO_URL" rbenv
cd rbenv
git reset --hard "$RBENV_REPO_REF"
# The tarball must include .git too because `rbenv --version`
# scans the Git history in order to determine its version
# number.
tar -zcf ../output/rbenv-src.tar.gz .
