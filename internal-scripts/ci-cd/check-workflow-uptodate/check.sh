#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)


"$ROOTDIR"/internal-scripts/generate-ci-cd-yaml.rb .github/workflows/ci-cd.yml.2

CHECKSUM_A=$(md5sum .github/workflows/ci-cd.yml | awk '{ print $1 }')
CHECKSUM_B=$(md5sum .github/workflows/ci-cd.yml.2 | awk '{ print $1 }')

if [[ "$CHECKSUM_A" = "$CHECKSUM_B" ]]; then
    echo 'Up-to-date!'
else
    echo 'ERROR: .github/workflows/ci-cd.yml is not up-to-date!'
    echo 'Please run this script, then commit and push:'
    echo
    echo '  ./internal-scripts/generate-ci-cd-yaml.rb'
    echo
    echo 'TIP: run this on your development machine to ensure generate-ci-cd-yaml.rb is run automatically as a Git pre-commit hook:'
    echo
    echo '  git config core.hooksPath .githooks'
    exit 1
fi
