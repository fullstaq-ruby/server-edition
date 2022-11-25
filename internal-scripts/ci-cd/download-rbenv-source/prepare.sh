#!/bin/bash
set -e
set -o pipefail

REPO_URL=$(ruby -ryaml -e 'puts YAML.load_file("config.yml")["rbenv"]["repo"]')
REF=$(ruby -ryaml -e 'puts YAML.load_file("config.yml")["rbenv"]["ref"]')
CACHE_BODY="$REPO_URL"$'\n'"$REF"
CACHE_KEY=$(md5sum <<<"$CACHE_BODY" | awk '{ print $1 }')

echo "Repo: $REPO_URL"
echo "Ref: $REF"
echo "Cache key: $CACHE_KEY"

{
    echo "repo_url=$REPO_URL"
    echo "ref=$REF"
    echo "cache_key=$CACHE_KEY"
} >> "$GITHUB_OUTPUT"
