#!/bin/bash
set -e

SELFDIR=$(dirname "$0")
ROOTDIR=$(cd "$SELFDIR/../../.." && pwd)
# shellcheck source=../../../lib/library.sh
source "$ROOTDIR/lib/library.sh"

echo '+ Adding Aptly repo'
echo deb http://repo.aptly.info/ squeeze main | sudo tee /etc/apt/sources.list.d/aptly.list
echo '+ Adding Aptly public key'
curl -fsSL https://www.aptly.info/pubkey.txt | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/aptly.gpg
run sudo apt update
run sudo apt install -y aptly
