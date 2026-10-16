# Sandbox VM

`sandbox.yaml` is a Lima configuration for a disposable Ubuntu VM. You use the VM to run an AI coding agent without supervision. The configuration assumes that code inside the VM is hostile. It keeps that code away from your Mac, your credentials, and your local network.

The VM has these limits:

- It has no access to the files on your Mac.
- It cannot use your SSH keys or your SSH agent.
- The user inside the VM cannot get root. `sudo` always fails.
- The VM cannot connect to your Mac, your LAN, or Tailscale addresses. It can connect to the internet.
- DNS lookups use DNS over TLS (port 853). Some networks block plain DNS (port 53) to public resolvers.
- If the hardening steps fail at boot, the VM shuts down.

## Requirements

You need Lima 2.0 or later on your Mac. If you installed Lima together with Colima, upgrade both:

```sh
brew update
brew upgrade lima colima
limactl --version
```

## How the VMs work

The `Makefile` uses two VMs:

- The base VM, `sandbox-base`, installs the packages one time and then stops. You never run the agent in the base VM.
- The task VM, `sandbox`, is a clone of the base VM. You run the agent in the task VM and delete it when the task is done.

A clone does not install packages again, so it starts in about 10 seconds. A new base VM takes about 2 minutes. The firewall and the sudo lock run again at each boot of each VM.

## Start the VM

Run the commands in this section on your Mac, in the directory that contains `sandbox.yaml`. The `Makefile` runs `limactl` for you. Run `make` without a target to see all targets.

1. Start the task VM:

   ```sh
   make start
   ```

   If the base VM does not exist, this command builds it first. The first build downloads the Ubuntu image and installs the packages. It takes about 2 minutes. Later starts clone the base VM and take about 10 seconds.

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

Run `make test` the first time you start a VM, and after each change to `sandbox.yaml`. It runs these tests in the VM:

| Test                                 | Expected result                                          |
| ------------------------------------ | -------------------------------------------------------- |
| `sudo -n true`                       | Fails. A password is required.                           |
| `~/password` exists                  | No. Lima did not write the password file.                |
| Connect to `192.168.5.2`, port 53    | Fails with "No route to host". This address is your Mac. |
| `curl -sI https://github.com`        | Works.                                                   |

Each line of the output starts with `ok` or `FAIL`. If a line starts with `FAIL`, do not run the agent in the VM.

## If the VM shuts down at start

If a hardening step fails at boot, the VM shuts down and `make start` or `make base` fails. The user inside the VM cannot read the system logs, so the VM writes the error to its serial console. To find the step that failed, run this command on your Mac:

```sh
grep -a -A20 'sandbox: hardening failed' ~/.lima/sandbox-base/serialv.log
```

For the task VM, use `~/.lima/sandbox/serialv.log`. If the output shows `Temporary failure resolving`, your network blocks DNS over TLS (port 853).

## Stop or delete the VM

To stop the task VM and keep its disk, run `make stop`.

To delete the task VM and its disk, run `make delete`. Delete the task VM when the task is done. The base VM stays, so the next `make start` is fast.

## Update or add software

The user inside the VM cannot install packages, because it has no root. The base VM installs and upgrades packages only when you build it. To add a package or to get security updates, do these steps on your Mac:

1. If you add a package, add it to the `apt-get install` line at the end of `sandbox.yaml`.
2. Run `make rebuild-base`. This command deletes the base VM and builds it again from `sandbox.yaml`.
3. Run `make recreate`. This command deletes the task VM and clones a new one from the new base VM.
4. Run `make test`.

Rebuild the base VM at least one time each month to get security updates.

## Make targets

| Target              | What it does                                                    | `limactl` command                                         |
| ------------------- | --------------------------------------------------------------- | --------------------------------------------------------- |
| `make start`        | Starts the task VM, or clones a new one from the base VM        | `limactl clone --start sandbox-base sandbox`              |
| `make shell`        | Opens a shell in the task VM                                    | `limactl shell sandbox`                                   |
| `make copy`         | Copies `SRC` into the home directory of the task VM             | `limactl copy -r ./scoped-credentials sandbox:~/`         |
| `make test`         | Runs the hardening tests in the task VM                         |                                                           |
| `make status`       | Shows the status of the task VM and the base VM                 | `limactl list sandbox sandbox-base`                       |
| `make stop`         | Stops the task VM and keeps its disk                            | `limactl stop sandbox`                                    |
| `make delete`       | Deletes the task VM and its disk. The base VM stays.            | `limactl delete -f sandbox`                               |
| `make recreate`     | Deletes the task VM and clones a new one from the base VM       |                                                           |
| `make base`         | Builds the base VM if it does not exist, then stops it          | `limactl start --name=sandbox-base ./sandbox.yaml`        |
| `make rebuild-base` | Deletes the base VM and builds it again                         |                                                           |
| `make validate`     | Makes sure that `sandbox.yaml` is a valid Lima configuration    | `limactl validate sandbox.yaml`                           |

To use a different VM name, set `NAME`. For example, run `make start NAME=other-sandbox`. The name of the base VM is then `other-sandbox-base`.

## Do

- Use scoped tokens that you can revoke. For example, use a fine-grained GitHub token for one repository and a separate API key for the agent.
- Revoke the tokens when you delete the VM.
- Get code out of the VM only with `git push` to a branch. Read the diff on your Mac before you merge it.
- Delete the VM after each task. A new VM starts from a clean state.

## Do not

- Do not copy your main SSH key, `~/.aws`, `~/.config`, or a full-access token into the VM. The VM has internet access, so the agent can send any file in the VM to any server.
- Do not set `plain: false`, and do not add `mounts` or `portForwards`. These settings connect the VM to your Mac.
- Do not set `passwordlessSudo: true`. The agent can then change the firewall as root.
- Do not run programs or scripts from the VM on your Mac before you read them.
- Do not remove the firewall section from `sandbox.yaml`. Without it, the agent can connect to your Mac and your LAN.
