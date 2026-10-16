#!/bin/bash
# Installs opencode, the AI coding agent for the terminal.
# https://opencode.ai
#
# Lima runs this script as root at each boot, after provision.sh. The next
# line stops the script when the tool is already installed, so only the first
# boot of the base VM installs it.
set -eux -o pipefail
command -v opencode >/dev/null && exit 0

# The installer always installs in $HOME/.opencode/bin. The script gives it a
# temporary home and then moves the program to /usr/local/bin, so the program
# belongs to root and the user cannot change it.
tmp=$(mktemp -d)
curl -fsSL https://opencode.ai/v2/install | HOME="$tmp" bash -s -- --no-modify-path
install -m 755 "$tmp/.opencode/bin/opencode" /usr/local/bin/opencode
rm -rf "$tmp"
