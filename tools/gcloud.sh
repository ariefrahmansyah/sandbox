#!/bin/bash
# Installs gcloud, the Google Cloud CLI, from the Google apt repository.
# https://cloud.google.com/sdk/docs/install
#
# Lima runs this script as root at each boot, after provision.sh. The next
# line stops the script when the tool is already installed, so only the first
# boot of the base VM installs it.
set -eux -o pipefail
command -v gcloud >/dev/null && exit 0

export DEBIAN_FRONTEND=noninteractive
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  -o /usr/share/keyrings/cloud.google.asc
cat >/etc/apt/sources.list.d/google-cloud-sdk.sources <<'SRC'
Types: deb
URIs: https://packages.cloud.google.com/apt
Suites: cloud-sdk
Components: main
Signed-By: /usr/share/keyrings/cloud.google.asc
SRC
apt-get update
apt-get install -y --no-install-recommends google-cloud-cli
apt-get clean
