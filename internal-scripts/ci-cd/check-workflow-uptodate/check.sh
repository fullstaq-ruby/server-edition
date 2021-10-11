#!/bin/bash
set -e
set -o pipefail

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)


"$ROOTDIR"/internal-scripts/generate-ci-cd-yaml.rb

if [[ -z "$(git status --porcelain --untracked-files=no .github/workflows)" ]]; then
    echo 'All workflow files up-to-date!'
else
    echo 'ERROR: one or more workflow files are not up-to-date!'
    git status --porcelain --untracked-files=no .github/workflows

    echo
    echo 'Please run this script, then commit and push:'
    echo
    echo '  ./internal-scripts/generate-ci-cd-yaml.rb'
    echo
    echo 'TIP: run this on your development machine to ensure generate-ci-cd-yaml.rb is run automatically as a Git pre-commit hook:'
    echo
    echo '  git config core.hooksPath .githooks'
    echo
    echo "Here's the difference:"
    git diff --color .github/workflows
    exit 1
fi
