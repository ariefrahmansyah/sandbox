#!/bin/bash
# Tests that the sandbox hardening works. `make test` runs this script as the
# user inside the VM. Each line of the output starts with "ok" or "FAIL". The
# script exits with 1 when a test fails.
set -u

host=192.168.5.2   # The Mac, as the VM sees it
fail=0
ok()   { echo "ok    $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

if sudo -n true 2>/dev/null; then bad "sudo works"; else ok "sudo is blocked"; fi

if [ -e ~/password ]; then bad "~/password exists"; else ok "~/password does not exist"; fi

# The firewall rejects the connection, so the error is "No route to host".
err=$(timeout 5 bash -c "</dev/tcp/$host/53" 2>&1)
if grep -qi "no route to host" <<<"$err"; then ok "host is blocked"
else bad "host is not blocked: $err"; fi

if curl -sSI -m 10 https://github.com >/dev/null; then ok "internet works"
else bad "internet does not work"; fi

extra=$(find / -xdev -type f -perm /6000 2>/dev/null | grep -vxF -f /etc/sandbox/setuid-allowed)
if [ -z "$extra" ]; then ok "only allowed setuid programs remain"
else bad "setuid programs not in /etc/sandbox/setuid-allowed:" $extra; fi

# One container run tests two things. "started" shows that containers run.
# Inside a container, pasta reports the firewall block as "Connection refused".
out=$(podman run --rm docker.io/library/bash:5 bash -c \
  "echo started; timeout 5 bash -c '</dev/tcp/$host/53'" 2>&1)
if ! grep -q started <<<"$out"; then bad "containers do not run: $out"
else
  ok "containers run"
  if grep -qiE "refused|no route to host" <<<"$out"; then ok "host is blocked from containers"
  else bad "host is not blocked from containers: $out"; fi
fi

exit $fail
