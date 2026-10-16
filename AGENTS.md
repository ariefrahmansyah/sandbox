# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A hardened, disposable Lima VM (macOS host, `vz`, Ubuntu 26.04) for running an AI coding agent unattended. Threat model: code inside the VM is hostile. It must not reach host files, host credentials, the host, or the LAN, and must not get root. Internet egress is allowed by design.

## Project map

- `sandbox.yaml` - Lima config. Its one `mode: system` provision entry points to `provision.sh` with `file:`
- `provision.sh` - root script that does all hardening at every boot. Lima embeds it (with `{{.Home}}`/`{{.User}}` intact) when it creates the VM
- `Makefile` - wraps `limactl`. Builds a base VM once, then clones it per task
- `tools/*.sh` - one root install script per tool (uv, gcloud, opencode). Kept out of `sandbox.yaml` on purpose. Same header in each: purpose + URL, when it runs, `set -eux -o pipefail`, `command -v` guard
- `tests/hardening.sh` - hardening checks. `make test` pipes it into the VM with `limactl shell $(NAME) bash -s`
- `README.md` - user-facing guide, written in simple English

## Architecture

- Two VMs: `$(NAME)-base` (default `sandbox-base`) is built from `sandbox.yaml` and `provision.sh`, installs packages once, then stays stopped. `$(NAME)` (default `sandbox`) is a `limactl clone` of it. A clone starts in about 8 s; a base build takes about 2 min.
- The provision script reruns on every boot of every VM: sudo lock, DNS over TLS, nftables egress firewall. Package install runs only once, guarded by the root-owned marker `/var/lib/sandbox/packages-done`, so clones skip it.
- Tools: `make base` writes `.build/$(BASE).yaml` with `base: sandbox.yaml` plus one `mode: system` `file:` entry per `tools/*.sh`, and builds from that. Lima runs the base's provision script first, so tools install after hardening. `limactl start --set` cannot add `file:` scripts (Lima embeds files before `--set`). Each tool script reruns every boot, so it must exit early when the tool exists.
- Fail closed: an `ERR` trap writes the failing line to `/dev/hvc0` and powers the VM off. The guest user cannot read logs, so debug from the host with `grep -a -A20 'sandbox: hardening failed' ~/.lima/<name>/serialv.log`.

<important if="you need to run commands to build, test, or manage the VM">

Run `make` (no target) to list targets. Key ones:

| Command | What it does |
|---|---|
| `make validate` | `limactl validate sandbox.yaml` and `bash -n` on all scripts |
| `make start` | Start `sandbox`, or build the base if missing and clone it |
| `make test` | Run the four hardening checks in the VM, prints `ok`/`FAIL`, nonzero on any failure |
| `make rebuild-base` then `make recreate` | Apply any change to `sandbox.yaml`, `provision.sh`, or `tools/` (clones never re-read them) |
| `make status` / `stop` / `delete` / `delete-base` / `delete-all` / `shell` / `copy SRC=...` | Day-to-day management |

Override `NAME=...` to run a separate pair (`NAME-base` follows). During a base build Lima prints nothing at "boot scripts must have finished" for about 2 minutes; that is apt running, not a hang.
</important>

<important if="you are editing provision.sh or Lima settings in sandbox.yaml">

- Use Lima template vars `{{.Home}}` and `{{.User}}`, not `LIMA_CIDATA_*` (Lima warns against those).
- The sudo lock depends on ordering: Lima's boot.sh writes `~/password` only when `~/.lima-password-set` is absent, and it runs after system provision scripts. The script recreates that marker, removes `~/password`, and runs `passwd -l` on every boot.
- Keep `upgradePackages: false`. Lima changes the instance ID on every boot, so its upgrade would rerun each boot; upgrades happen in the once-only package block.
- DNS uses DNS over TLS (port 853) because the user's network blocks outbound port 53 to public resolvers. `hostResolver` is off, and the firewall blocks 192.168.5.2 (the host).
- Any command that can fail in the script powers the VM off. Use `|| true` only for steps that are genuinely optional.
- With `passwordlessSudo: false`, Lima logs a failed `sudo cat param.env` readiness check and an "experimental" warning. Both are expected and harmless.
- The public IPv4 is not blocked on purpose. Behind carrier-grade NAT, lookup services report different addresses from a rotating pool, so a boot-time block fails. The README warns against networks with router port forwards instead.
- Setuid is an allowlist: `provision.sh` writes `/etc/sandbox/setuid-allowed` and strips every other setuid/setgid bit at each boot. The test reads the same file, so the list lives in one place. Keep `newuidmap`/`newgidmap` and `fusermount3` for rootless Podman. Tools run after the strip, so their setuid bits go on the next boot.
- Package split: `provision.sh` installs only what hardening and `make test` need (Podman included). Everything else goes in `tools/`.
- Containers are rootless Podman (`podman-docker` gives a `docker` command). Never install rootful Docker: its socket is root, and bridge traffic uses the forward hook, which the firewall drops. Rootless traffic goes through `pasta` and the output chain.
- `plain: false`, `mounts`, `portForwards`, `passwordlessSudo: true`, and SSH agent forwarding each break the threat model. They expose the host or give the agent root.
</important>

<important if="you are changing tests/hardening.sh">

The host check uses bash `/dev/tcp` and expects "no route to host" (the nftables `admin-prohibited` reject). It used curl before, but curl's error message hid the errno and gave false failures. The container host check accepts "refused" too, because `pasta` turns the reject into a TCP reset inside the container. After a change, run `make test` against a running VM.
</important>

<important if="you are editing README.md or comments in the scripts">

Keep the simple-English style: no contractions, no should/may/might/could/would, no em-dashes, no semicolons, no bold, and "make sure that" instead of check/verify. Keep the make-targets table in sync with the `Makefile` and the test table in sync with `tests/hardening.sh`. The same style applies to comments in `sandbox.yaml`, `provision.sh`, `tools/*.sh`, and `tests/hardening.sh`.
</important>
