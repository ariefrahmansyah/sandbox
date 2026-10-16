#!/bin/bash
# Installs Codex, the AI coding agent for the terminal from OpenAI.
# https://chatgpt.com/codex/install.sh
#
# Lima runs this script as root at each boot, after provision.sh. The next
# line stops the script when the tool is already installed, so only the first
# boot of the base VM installs it.
set -eux -o pipefail
command -v codex >/dev/null && exit 0

# A Codex release has more than one file: codex, codex-code-mode-host, rg, and
# bwrap. The installer puts the release in $CODEX_HOME/packages and puts a link
# to codex in $CODEX_INSTALL_DIR. With these variables, the release goes in
# /opt/codex and the link goes in /usr/local/bin, so the program belongs to
# root and the user cannot change it. The user keeps its own settings in
# ~/.codex. The temporary home stops the installer from a change to a shell
# profile, and CODEX_NON_INTERACTIVE stops its questions.
tmp=$(mktemp -d)
curl -fsSL https://chatgpt.com/codex/install.sh |
  env HOME="$tmp" CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
    CODEX_NON_INTERACTIVE=1 sh
rm -rf "$tmp"
