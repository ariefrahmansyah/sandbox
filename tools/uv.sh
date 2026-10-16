#!/bin/bash
# Installs uv and uvx, the Python package and project manager.
# https://docs.astral.sh/uv/
#
# Lima runs this script as root at each boot, after provision.sh. The next
# line stops the script when the tool is already installed, so only the first
# boot of the base VM installs it.
set -eux -o pipefail
command -v uv >/dev/null && exit 0

curl -fsSL https://astral.sh/uv/install.sh |
  env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
