#!/bin/bash
# Hardens the sandbox VM. Lima runs this script as root at each boot of each
# VM, before the tool scripts in tools/ and before the user can log in.
#
# The script has five steps:
#   1. Lock root for the user.
#   2. Use DNS over TLS.
#   3. Load the firewall.
#   4. Install packages (first boot of the base VM only).
#   5. Remove setuid bits that the user does not need.
#
# Lima replaces {{.Home}} and {{.User}} with the home directory and the name
# of the user in the VM.
set -eux -o pipefail
export DEBIAN_FRONTEND=noninteractive

# If a step fails, the VM must not run half hardened. The trap writes the
# error to the serial console and turns the VM off. The serial console goes
# to ~/.lima/<vm>/serialv.log on the Mac. The user in the VM has no root, so
# the user cannot read the logs inside the VM.
trap 'line=$LINENO cmd=$BASH_COMMAND; { echo "sandbox: hardening failed at line $line: $cmd, powering off"; tail -n 20 /var/log/cloud-init-output.log; } | tee /dev/hvc0 >&2; systemctl poweroff' ERR

# --- 1. No root for the user ------------------------------------------------
# Lima writes a random sudo password to ~/password when the marker file
# ~/.lima-password-set does not exist. Lima does this after this script, so
# the script creates the marker at each boot. The user can delete the marker,
# but the next boot creates it again.
touch "{{.Home}}/.lima-password-set"
rm -f "{{.Home}}/password"
passwd -l "{{.User}}"
# Members of these groups can get root.
for g in sudo admin lxd docker disk; do
  gpasswd -d "{{.User}}" "$g" 2>/dev/null || true
done

# --- 2. DNS over TLS --------------------------------------------------------
# Some networks block plain DNS (port 53) to public resolvers. DNS over TLS
# uses port 853. Keep these resolvers the same as `dns:` in sandbox.yaml.
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/90-sandbox-dot.conf <<'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
DNSOverTLS=yes
Domains=~.
EOF
systemctl restart systemd-resolved

# --- 3. Firewall ------------------------------------------------------------
# The VM can connect to the internet. It cannot connect to these addresses:
#   - 192.168.5.2, the Mac (Lima gateway), and the rest of the LAN
#   - 100.64.0.0/10, Tailscale and carrier-grade NAT
#   - 169.254.0.0/16, link-local and cloud metadata
#   - Multicast
# Replies to connections from the Mac (`limactl shell` uses SSH) still work.
# The image has nftables. The install line is only a fallback.
command -v nft >/dev/null || { apt-get update; apt-get install -y nftables; }
cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet sandbox {
  set blocked_v4 {
    type ipv4_addr; flags interval
    elements = {
      10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
      100.64.0.0/10, 169.254.0.0/16, 224.0.0.0/4
    }
  }
  set blocked_v6 {
    type ipv6_addr; flags interval
    elements = { fc00::/7, fe80::/10, ff00::/8 }
  }

  chain output {
    type filter hook output priority filter; policy accept;
    oifname "lo" accept
    ct state established,related accept
    udp sport 68 udp dport 67 accept      # DHCP lease renewal
    meta l4proto ipv6-icmp accept         # IPv6 neighbor discovery
    ip daddr @blocked_v4 limit rate 10/minute log prefix "sandbox-egress-block: "
    ip daddr @blocked_v4 counter reject with icmpx type admin-prohibited
    ip6 daddr @blocked_v6 counter reject with icmpx type admin-prohibited
  }

  # The VM does not route traffic. Rootless Podman sends container traffic
  # through pasta, which uses the output chain above as the user. Rootful
  # Docker uses this chain, so this rule blocks it.
  chain forward {
    type filter hook forward priority filter; policy drop;
  }
}
EOF
nft -f /etc/nftables.conf
nft list table inet sandbox >/dev/null
systemctl enable nftables

# --- 4. Packages (first boot of the base VM only) ---------------------------
# This step installs the packages that the hardening and `make test` need.
# Other software goes in tools/. The user cannot install packages, and the
# root-owned marker file stops the user from running this step again. Clones
# get the marker from the base VM, so they skip this step.
if [ ! -f /var/lib/sandbox/packages-done ]; then
  apt-get update
  apt-get upgrade -y
  apt-get install -y --no-install-recommends \
    git curl ca-certificates build-essential jq ripgrep \
    podman podman-docker uidmap passt fuse-overlayfs dbus-user-session
  # Rootless Podman needs subordinate user and group IDs. Do not install
  # rootful Docker. Its socket gives root, and its traffic skips the output
  # chain.
  grep -q "^{{.User}}:" /etc/subuid || usermod --add-subuids 100000-165535 "{{.User}}"
  grep -q "^{{.User}}:" /etc/subgid || usermod --add-subgids 100000-165535 "{{.User}}"
  touch /etc/containers/nodocker
  apt-get clean
  mkdir -p /var/lib/sandbox
  touch /var/lib/sandbox/packages-done
fi

# --- 5. Setuid bits ---------------------------------------------------------
# Each setuid or setgid program is a possible way to get root. The script
# removes the bits from all programs except the ones in this list. sudo stays
# because it fails anyway (the password is locked). Rootless Podman needs
# newuidmap, newgidmap, and fusermount3. The tests in tests/hardening.sh read
# this list from /etc/sandbox/setuid-allowed.
mkdir -p /etc/sandbox
cat >/etc/sandbox/setuid-allowed <<'EOF'
/usr/bin/sudo.ws
/usr/lib/cargo/bin/sudo
/usr/bin/mount
/usr/bin/umount
/usr/bin/fusermount3
/usr/bin/newuidmap
/usr/bin/newgidmap
/usr/lib/dbus-1.0/dbus-daemon-launch-helper
EOF
# The tool scripts run after this step. If a tool adds a setuid program, the
# next boot removes the bit. Each clone boots at least one time before use.
# grep exits with 1 when it finds no line, so `|| true` keeps the trap quiet.
find / -xdev -type f -perm /6000 | { grep -vxF -f /etc/sandbox/setuid-allowed || true; } |
  xargs -r chmod u-s,g-s
