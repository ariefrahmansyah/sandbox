# Sandbox VM

This project creates a disposable Ubuntu VM on your Mac with Lima. You use the VM to run an AI coding agent without supervision. The configuration assumes that code inside the VM is hostile. It keeps that code away from your Mac, your credentials, and your local network.

The VM has these limits:

- It has no access to the files on your Mac.
- It cannot use your SSH keys or your SSH agent.
- The user inside the VM cannot get root. `sudo` always fails.
- The VM cannot connect to your Mac, your LAN, or Tailscale addresses. It can connect to the internet.
- Only a short list of setuid programs remains. Each setuid program is a possible way to get root.
- DNS lookups use DNS over TLS (port 853). Some networks block plain DNS (port 53) to public resolvers.
- If a hardening step fails at boot, the VM shuts down.

The agent can run containers with rootless Podman, and it can use the tools in the `tools` directory, such as `uv`, `gcloud`, `opencode`, `claude`, and `codex`.

## Files

| File                 | What it contains                                             | When it runs                          |
| -------------------- | ------------------------------------------------------------ | ------------------------------------- |
| `sandbox.yaml`       | The VM hardware and the Lima settings                         | When Lima creates the VM              |
| `provision.sh`       | The hardening script: sudo lock, DNS, firewall, packages, setuid | As root, at each boot of each VM   |
| `tools/*.sh`         | One install script for each tool                             | As root, at each boot, after `provision.sh` |
| `tests/hardening.sh` | The hardening tests                                          | When you run `make test`              |
| `Makefile`           | The commands that you use. They run `limactl` for you.       | When you run `make`                   |

## Why there are two VMs

Package and tool installs take a few minutes. You want a new, clean VM for each task, but you do not want to wait for the installs each time. For this reason, the `Makefile` uses two VMs:

- The base VM, `sandbox-base`, installs the packages and the tools one time and then stops. You never run the agent in the base VM.
- The task VM, `sandbox`, is a clone of the base VM. You run the agent in the task VM and delete it when the task is done.

A clone gets the installed software from the base VM, so it starts in about 10 seconds. The hardening in `provision.sh` runs again at each boot of each VM.

The word "base" also occurs in `sandbox.yaml`, as `base: template:_images/ubuntu-26.04`. That is a Lima template that gives the Ubuntu image settings. It is not the base VM.

## Requirements

You need Lima 2.0 or later on your Mac. If you installed Lima together with Colima, upgrade both:

```sh
brew update
brew upgrade lima colima
limactl --version
```

## Start the VM

Run the commands in this section on your Mac, in the directory that contains `sandbox.yaml`. Run `make` without a target to see all targets.

1. Start the task VM:

   ```sh
   make start
   ```

   If the base VM does not exist, this command builds it first. The first build downloads the Ubuntu image, installs the packages and the tools, and takes a few minutes. Lima prints nothing while it waits for "boot scripts must have finished". Later starts clone the base VM and take about 10 seconds.

2. Make sure that the hardening works. For the tests, see the next section.

   ```sh
   make test
   ```

3. Copy your scoped credentials into the VM. The default source is `./scoped-credentials`. To copy a different file or directory, set `SRC`:

   ```sh
   make copy SRC=./scoped-credentials
   ```

4. Open a shell in the VM:

   ```sh
   make shell
   ```

5. In the VM, clone your repository with `git clone` and start the agent.

## Make sure that the hardening works

Run `make test` the first time you start a VM, and after each change to `sandbox.yaml`, `provision.sh`, or `tools`. The command runs `tests/hardening.sh` in the task VM. The script runs these tests:

| Test                                        | Expected result                                          |
| ------------------------------------------- | -------------------------------------------------------- |
| `sudo -n true`                              | Fails. A password is required.                           |
| `~/password` exists                         | No. Lima did not write the password file.                |
| Connect to `192.168.5.2`, port 53           | Fails with "No route to host". This address is your Mac. |
| `curl -sI https://github.com`               | Works.                                                   |
| Setuid and setgid programs                  | Only the programs in `/etc/sandbox/setuid-allowed` remain. |
| `podman run` a small image                  | Works. Podman downloads the `bash` image the first time. |
| Connect to `192.168.5.2` from a container   | Fails with "Connection refused". The firewall blocks it. |

Each line of the output starts with `ok` or `FAIL`. If a line starts with `FAIL`, do not run the agent in the VM.

## Containers

The VM has rootless Podman and the `podman-docker` package. The agent can use `docker run` and `docker build` as usual. The commands run Podman.

The VM does not have the Docker daemon. Access to the Docker daemon gives root, and its container traffic does not go through the firewall rules for the VM. Do not add the `docker.io` or `docker-ce` packages to `provision.sh` or to a tool script.

Some tools need more than the Podman CLI. Some tools connect to a Docker socket. Examples are Docker Compose, Testcontainers, and the Docker SDKs. Other tools read fields that only the Docker CLI has, such as `ServerVersion` in `docker info`. The Podman CLI does not have these fields, so these tools report that the Docker daemon is not reachable.

For these tools, `tools/docker-cli.sh` does three things:

- It installs the Docker CLI in `/usr/local/bin/docker`. It does not install the Docker daemon. `/usr/local/bin` comes before `/usr/bin` in `PATH`, so `docker` runs the Docker CLI and not the `podman-docker` shim.
- It starts the Podman API socket for the user at login. The socket is `/run/user/<uid>/podman/podman.sock`.
- It sets `DOCKER_HOST` to the socket in `/etc/profile.d/docker-host.sh`.

The Docker CLI sends each command to Podman through the socket. The socket belongs to the VM user and not to root, so it does not give root. Containers that start through the socket are rootless, and the firewall applies to them. To make sure that the socket works, run `docker info`. The server version is the Podman version.

Rootless containers run in a user namespace. The root user in a container is the normal VM user outside the container. Container network traffic goes through `pasta` as the VM user, so the firewall applies to it. Inside a container, a blocked connection fails with "Connection refused" and not "No route to host".

Images use disk space in the VM. The VM disk is 20 GiB. To make it larger, change `disk` in `sandbox.yaml` and rebuild the base VM.

## Tools

The base VM installs the tools in the `tools` directory. Each tool has one script. The VM has these tools now:

| Script            | Tool                                       | Installed in     |
| ----------------- | ------------------------------------------ | ---------------- |
| `tools/uv.sh`     | `uv` and `uvx`, the Python project manager | `/usr/local/bin` |
| `tools/gcloud.sh` | `gcloud`, the Google Cloud CLI             | `/usr/bin` (apt) |
| `tools/opencode.sh` | `opencode`, the AI coding agent          | `/usr/local/bin` |
| `tools/docker-cli.sh` | `docker`, the Docker CLI for the Podman socket | `/usr/local/bin` |
| `tools/claude.sh` | `claude`, Claude Code, the AI coding agent | `/usr/local/bin` |
| `tools/codex.sh`  | `codex`, the AI coding agent from OpenAI   | `/usr/local/bin`, with the files in `/opt/codex` |

The tools in `/usr/local/bin` belong to root, so they cannot update themselves. For example, Claude Code and Codex cannot install a new version. To get new versions, rebuild the base VM. For the steps, see "Update the VM".

The tool list is not in `sandbox.yaml`. When `make base` builds the base VM, it writes `.build/sandbox-base.yaml`. That file uses `sandbox.yaml` as its Lima base template and adds each `tools/*.sh` script as a provision script. Make writes the file again at each build, so git ignores it.

Use `provision.sh` only for the packages that the hardening and the tests need, such as Podman. Use `tools` for all other software.

To add a tool, do these steps:

1. Copy `tools/uv.sh` to a new file in the `tools` directory, for example `tools/node.sh`.
2. Change the comment at the top of the script. It must name the tool and its install page.
3. Change the `command -v` line to the command of the new tool, for example `command -v node >/dev/null && exit 0`. The script runs at each boot, and this line stops it when the tool is already installed.
4. Write the install commands. Install the tool in `/usr/local/bin` or with `apt-get`. The script runs as root, so the user in the VM cannot change the tool.
5. Run `make rebuild-base`, then `make recreate`, then `make test`.

Add only tools from sources that you trust. The scripts run as root and download software from the internet. If a tool script fails, `make base` fails.

To remove a tool, delete its script and rebuild the base VM.

## Update the VM

The user inside the VM cannot install packages, because it has no root. The base VM installs and upgrades the software only when you build it. To get security updates or to apply a change to `sandbox.yaml`, `provision.sh`, or `tools`, do these steps on your Mac:

1. Run `make rebuild-base`. This command deletes the base VM and builds it again.
2. Run `make recreate`. This command deletes the task VM and clones a new one from the new base VM.
3. Run `make test`.

Rebuild the base VM at least one time each month. The kernel updates are a part of these updates.

## If the VM shuts down at start

If a hardening step fails at boot, the VM shuts down and `make start` or `make base` fails. The user inside the VM cannot read the system logs, so the VM writes the error to its serial console. To find the step that failed, run this command on your Mac:

```sh
grep -a -A20 'sandbox: hardening failed' ~/.lima/sandbox-base/serialv.log
```

For the task VM, use `~/.lima/sandbox/serialv.log`. If the output shows `Temporary failure resolving`, your network blocks DNS over TLS (port 853).

## Stop or delete the VM

To stop the task VM and keep its disk, run `make stop`.

To delete the task VM and its disk, run `make delete`. Delete the task VM when the task is done. The base VM stays, so the next `make start` is fast.

To delete the base VM, run `make delete-base`. To delete both VMs, run `make delete-all`. The next `make start` then builds a new base VM, and that takes a few minutes.

## Make targets

| Target              | What it does                                                    | `limactl` command                                            |
| ------------------- | --------------------------------------------------------------- | ------------------------------------------------------------ |
| `make start`        | Starts the task VM, or clones a new one from the base VM        | `limactl clone --start sandbox-base sandbox`                 |
| `make shell`        | Opens a shell in the task VM                                    | `limactl shell sandbox`                                      |
| `make copy`         | Copies `SRC` into the home directory of the task VM             | `limactl copy -r ./scoped-credentials sandbox:~/`            |
| `make test`         | Runs `tests/hardening.sh` in the task VM                        | `limactl shell sandbox bash -s <tests/hardening.sh`          |
| `make status`       | Shows the status of the task VM and the base VM                 | `limactl list sandbox sandbox-base`                          |
| `make stop`         | Stops the task VM and keeps its disk                            | `limactl stop sandbox`                                       |
| `make delete`       | Deletes the task VM and its disk. The base VM stays.            | `limactl delete -f sandbox`                                  |
| `make delete-base`  | Deletes the base VM and its disk. The task VM stays.            | `limactl delete -f sandbox-base`                             |
| `make delete-all`   | Deletes the task VM and the base VM                             |                                                              |
| `make recreate`     | Deletes the task VM and clones a new one from the base VM       |                                                              |
| `make base`         | Builds the base VM if it does not exist, then stops it          | `limactl start --name=sandbox-base .build/sandbox-base.yaml` |
| `make rebuild-base` | Deletes the base VM and builds it again                         |                                                              |
| `make validate`     | Makes sure that the Lima configuration and the scripts are valid | `limactl validate .build/sandbox-base.yaml`                 |

To use a different VM name, set `NAME`. For example, run `make start NAME=other-sandbox`. The name of the base VM is then `other-sandbox-base`.

## Do

- Use scoped tokens that you can revoke. For example, use a fine-grained GitHub token for one repository and a separate API key for the agent.
- Revoke the tokens when you delete the VM.
- Get code out of the VM only with `git push` to a branch. Read the diff on your Mac before you merge it.
- Delete the VM after each task. A new VM starts from a clean state.

## Do not

- Do not copy your main SSH key, `~/.aws`, `~/.config`, or a full-access token into the VM. The VM has internet access, so the agent can send any file in the VM to any server.
- Do not set `plain: false`, and do not add `mounts` or `portForwards` to `sandbox.yaml`. These settings connect the VM to your Mac.
- Do not set `passwordlessSudo: true`. The agent can then change the firewall as root.
- Do not run programs or scripts from the VM on your Mac before you read them.
- Do not remove the firewall step from `provision.sh`. Without it, the agent can connect to your Mac and your LAN.
- Do not run the VM on a network where your router forwards ports to LAN devices. The VM can connect to the public IP address of the network, and the router can send that traffic to a LAN device.
