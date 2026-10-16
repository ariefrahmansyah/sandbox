# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A hardened, disposable Lima VM (macOS host, `vz`, Ubuntu 26.04) for running an AI coding agent unattended. Threat model: code inside the VM is hostile. It must not reach host files, host credentials, the host, or the LAN, and must not get root. Internet egress is allowed by design.

## Project map

- `sandbox.yaml` - Lima config plus one `mode: system` provision script that does all hardening at every boot
- `Makefile` - wraps `limactl`. Builds a base VM once, then clones it per task
- `README.md` - user-facing guide, written in simple English

## Architecture

- Two VMs: `$(NAME)-base` (default `sandbox-base`) is built from `sandbox.yaml`, installs packages once, then stays stopped. `$(NAME)` (default `sandbox`) is a `limactl clone` of it. A clone starts in about 8 s; a base build takes about 2 min.
- The provision script reruns on every boot of every VM: sudo lock, DNS over TLS, nftables egress firewall. Package install runs only once, guarded by the root-owned marker `/var/lib/sandbox/packages-done`, so clones skip it.
- Fail closed: an `ERR` trap writes the failing line to `/dev/hvc0` and powers the VM off. The guest user cannot read logs, so debug from the host with `grep -a -A20 'sandbox: hardening failed' ~/.lima/<name>/serialv.log`.

<important if="you need to run commands to build, test, or manage the VM">

Run `make` (no target) to list targets. Key ones:

| Command | What it does |
|---|---|
| `make validate` | `limactl validate sandbox.yaml` |
| `make start` | Start `sandbox`, or build the base if missing and clone it |
| `make test` | Run the four hardening checks in the VM, prints `ok`/`FAIL`, nonzero on any failure |
| `make rebuild-base` then `make recreate` | Apply any change to `sandbox.yaml` (clones never re-read it) |
| `make status` / `stop` / `delete` / `shell` / `copy SRC=...` | Day-to-day management |

Override `NAME=...` to run a separate pair (`NAME-base` follows). During a base build Lima prints nothing at "boot scripts must have finished" for about 2 minutes; that is apt running, not a hang.
</important>

<important if="you are editing the provision script or Lima settings in sandbox.yaml">

- Use Lima template vars `{{.Home}}` and `{{.User}}`, not `LIMA_CIDATA_*` (Lima warns against those).
- The sudo lock depends on ordering: Lima's boot.sh writes `~/password` only when `~/.lima-password-set` is absent, and it runs after system provision scripts. The script recreates that marker, removes `~/password`, and runs `passwd -l` on every boot.
- Keep `upgradePackages: false`. Lima changes the instance ID on every boot, so its upgrade would rerun each boot; upgrades happen in the once-only package block.
- DNS uses DNS over TLS (port 853) because the user's network blocks outbound port 53 to public resolvers. `hostResolver` is off, and the firewall blocks 192.168.5.2 (the host).
- Any command that can fail in the script powers the VM off. Use `|| true` only for steps that are genuinely optional.
- With `passwordlessSudo: false`, Lima logs a failed `sudo cat param.env` readiness check and an "experimental" warning. Both are expected and harmless.
- `plain: false`, `mounts`, `portForwards`, `passwordlessSudo: true`, and SSH agent forwarding each break the threat model. They expose the host or give the agent root.
</important>

<important if="you are changing the hardening tests in the Makefile">

The host check uses bash `/dev/tcp` and expects "no route to host" (the nftables `admin-prohibited` reject). It used curl before, but curl's error message hid the errno and gave false failures. After a change, run `make test` against a running VM.
</important>

<important if="you are editing README.md">

Keep the simple-English style: no contractions, no should/may/might/could/would, no em-dashes, no semicolons, no bold, and "make sure that" instead of check/verify. Keep the make-targets table and test table in sync with the `Makefile`.
</important>
