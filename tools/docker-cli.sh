#!/bin/bash
# Installs the Docker CLI and connects it to the rootless Podman API socket.
# https://docs.docker.com/engine/install/binaries/
#
# Lima runs this script as root at each boot, after provision.sh. The next
# line stops the script when the tool is already installed, so only the first
# boot of the base VM installs it. The test uses the path and not
# `command -v docker`, because the podman-docker shim is /usr/bin/docker.
set -eux -o pipefail
[ -x /usr/local/bin/docker ] && exit 0

# Some tools read fields that only the Docker CLI has, such as the
# ServerVersion field of `docker info --format`. The podman-docker shim runs the
# Podman CLI, and the Podman CLI does not have these fields. This script
# installs only the client binary. It does not install the Docker daemon.
# /usr/local/bin comes before /usr/bin in PATH, so this client replaces the
# shim.
url=https://download.docker.com/linux/static/stable/$(uname -m)
tgz=$(curl -fsSL "$url/" | grep -oE 'docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz' | sort -uV | tail -1)
tmp=$(mktemp -d)
curl -fsSL "$url/$tgz" | tar -xz -C "$tmp" docker/docker
install -m 755 "$tmp/docker/docker" /usr/local/bin/docker
rm -rf "$tmp"

# Start the Podman API socket for each user at login. The socket belongs to
# the user and not to root.
systemctl --global enable podman.socket

# Point the Docker CLI and the Docker SDKs at the socket.
cat >/etc/profile.d/docker-host.sh <<'EOF'
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
EOF
