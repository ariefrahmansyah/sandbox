#!/bin/bash
# Installs Claude Code, the AI coding agent for the terminal.
# https://claude.ai/install.sh
#
# Lima runs this script as root at each boot, after provision.sh. The next
# line stops the script when the tool is already installed, so only the first
# boot of the base VM installs it.
set -eux -o pipefail
command -v claude >/dev/null && exit 0

# The installer always installs in $HOME/.local. The script gives it a
# temporary home and then moves the program to /usr/local/bin, so the program
# belongs to root and the user cannot change it. ~/.local/bin/claude is a link
# to the program, so readlink finds the program file.
tmp=$(mktemp -d)
curl -fsSL https://claude.ai/install.sh | HOME="$tmp" bash
install -m 755 "$(readlink -f "$tmp/.local/bin/claude")" /usr/local/bin/claude
rm -rf "$tmp"
