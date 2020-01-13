#!/bin/bash
# Extracts the Rbenv source tarball, which we downloaded
# as an artifact.
set -e

mkdir rbenv
tar -C rbenv -xzf rbenv-src.tar.gz
