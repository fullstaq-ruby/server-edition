#!/bin/bash
# Checks whether the Rbenv version specified in
# config.yml matches the actual Rbenv version.
set -e

EXPECTED_RBENV_VERSION=$(./rbenv/bin/rbenv --version | awk '{ print $2 }' | sed -E 's/(.+)-.*/\1/')
ACTUAL_RBENV_VERSION=$(ruby -ryaml -e 'puts YAML.load_file("config.yml")["rbenv"]["version"]')

if [[ "$EXPECTED_RBENV_VERSION" = "$ACTUAL_RBENV_VERSION" ]]; then
    echo 'All good!'
else
    echo 'ERROR: the Rbenv version in config.yml is wrong.'
    echo "Expected: $EXPECTED_RBENV_VERSION"
    echo "  Actual: $ACTUAL_RBENV_VERSION"
    echo
    echo "Please open config.yml and edit rbenv.version"
    exit 1
fi
