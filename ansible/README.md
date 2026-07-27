# ansible/

Ansible playbooks and roles for configuring self-hosted infrastructure: LXC/VM hosts reachable over Tailscale, and Proxmox VE hosts on the local LAN.

## Playbooks

| Playbook | Hosts group | Purpose |
|----------|-------------|---------|
| `core.yaml` | `core` | Edge ingress device / webserver config |
| `pve.yaml` | `pve_hosts` | Converges Proxmox VE hosts to desired state via the `pve_host` role |
| `lxc-bootstrap.yaml` | Play 1: `{{ lxc_pve_host }}` (a PVE host). Play 2: `lxc_new` (dynamic) | One-shot: bootstraps an already-created LXC container. Play 1 preps it from the PVE host (`lxc_prepare` role: TUN device, IP discovery). Play 2 connects to the container directly over SSH (`lxc_bootstrap` role: `ansible` user, sudo, Tailscale) |

## Roles

| Role | Purpose |
|------|---------|
| `roles/pve_host/` | Idempotent post-install config for Proxmox VE nodes: disables the enterprise repo, enables the no-subscription repo, patches the Web/Mobile UI subscription nag, keeps HA services (corosync/pve-ha-lrm/pve-ha-crm) running if the node is clustered, and keeps packages up to date. Reimplements the useful parts of community-scripts' `post-pve-install.sh` without the interactive `whiptail` prompts. |
| `roles/lxc_prepare/` | Runs on the PVE host (needs `pct`). Adds the TUN device to an existing container's LXC config, reboots it only if that changed, then discovers its IP and registers it as a dynamic inventory host (`lxc_new` group) for the next play. |
| `roles/lxc_bootstrap/` | Runs directly against the container over SSH (as `root`, using the key you set at container-creation time — no `pct push`/`pct exec` needed). Reinforces your GitHub SSH key on `root`, creates a passwordless-sudo `ansible` user (no local SSH key - reachable only via Tailscale SSH), configures root auto-login on the console getty (opt-out via `lxc_bootstrap_console_autologin: false`), installs Tailscale via the official install script (`https://tailscale.com/install.sh`), joins the tailnet with `--ssh` automatically if an auth key was provided, and adds the resulting host to `inventory.yaml`'s `lxc` group automatically. |

## Running against Proxmox VE hosts (LAN)

`pve_hosts` entries in `inventory.yaml` connect as `root` over raw LAN IPs (e.g. `192.168.1.144`) — not over Tailscale, so this is run from a machine on the same LAN, not from CI.

### Prerequisite: add your SSH key first

On a freshly-installed PVE node you won't have SSH access yet, so Ansible can't connect. Add your public key via the Proxmox web UI's **Datacenter → node → Shell** (noVNC console, already root by default), then paste:

```bash
curl -fsSL https://github.com/<your-github-username>.keys >> ~/.ssh/authorized_keys
```

Repeat for every host in the `pve_hosts` group. Once that's done, confirm you can connect directly (`ssh root@<host-ip>`) before running Ansible.

### `caba-host` + `gateway-host` are clustered ("weinbender-home")

Both nodes are joined into a real corosync cluster. `pve_host_ha_enabled` defaults to `true`, so the role keeps `corosync`/`pve-ha-crm`/`pve-ha-lrm` running (only on nodes that actually have `/etc/pve/corosync.conf` — otherwise it just warns). **Do not** flip this to `false` while the cluster is in use — it will stop and disable corosync on that node, which breaks `pmxcfs` (`/etc/pve`) writes on both nodes until corosync is started again.

If `/etc/pve` writes ever start failing with `I/O error` or `Permission denied`, check corosync first: `systemctl status corosync` and `pvecm status`. `pmxcfs` refuses writes when it can't reach quorum.

### Apply

```bash
cd ansible
make check-pve   # dry run (--check --diff)
make run-pve     # apply for real
```

## Bootstrapping an LXC container

Create the container in the Proxmox web UI first (**Create CT**), including your SSH public key on the dialog's Confirm/SSH page — that gives you initial root access without any chicken-and-egg bootstrap problem. Then run `lxc-bootstrap.yaml` (no `--limit` needed — the target PVE host and CTID are passed as extra-vars, and play 2's target host is discovered dynamically):

```bash
make bootstrap-lxc PVE_HOST=caba-host
# Container ID (CTID) to bootstrap on caba-host: 105
# Tailscale auth key (blank to skip joining the tailnet now): <hidden input>
```

`CTID` and `TS_AUTHKEY` can also be passed directly (e.g. for scripting) to skip their prompts: `make bootstrap-lxc PVE_HOST=caba-host CTID=105 TS_AUTHKEY=tskey-...`. Generate a one-off, expiring auth key from the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys) — leave the prompt blank to skip joining and run `sudo tailscale up --ssh` manually later instead.

**Play 1** (`lxc_prepare`, runs on `caba-host` via `pct`):
1. Waits for the container to accept `pct exec` (useful right after creation while it's still starting)
2. Adds the TUN device to its LXC config and reboots the container only if that changed
3. Runs `hostname -I` inside the container and registers the IP as a dynamic host (`lxc_new` group) for play 2

**Play 2** (`lxc_bootstrap`, connects directly to the container over SSH as `root`):
1. Waits for outbound network connectivity (HTTPS HEAD request, retried) before doing anything network-dependent — the container may have just rebooted in play 1
2. Upgrades all installed packages (`apt-get upgrade`) — opt out via `lxc_bootstrap_upgrade_packages: false`
3. Reinforces your GitHub SSH key(s) on `root` (in case they weren't set, or were rotated, since container creation)
4. Creates an `ansible` user with passwordless sudo — **no local SSH key**; it's intentionally reachable only via Tailscale SSH, not plain SSH (see `roles/lxc_bootstrap/defaults/main.yaml` for all options)
5. Configures root auto-login on the container's console getty (systemd `agetty --autologin root` override, or `/etc/inittab` on Alpine) — the Proxmox web UI's noVNC console then drops straight to a root shell with no login prompt. Set `lxc_bootstrap_console_autologin: false` to opt out.
6. Installs the Tailscale package
7. If a Tailscale auth key was given and the node isn't already joined, runs `tailscale up --authkey=... --ssh` (enabling Tailscale SSH; the task uses `no_log: true` so the key never appears in Ansible's output/logs)
8. Sources the resulting Tailscale DNS hostname (`tailscale status --self --json` → `.Self.DNSName`)
9. Adds that hostname to `inventory.yaml`'s `lxc` group automatically: reads the file (`slurp` + `from_yaml`), merges in the new host (`combine`), writes it back (`to_nice_yaml` + `copy`) — idempotent since `copy` only reports changed when content actually differs, and merging the same host twice produces identical output

After it finishes: `root@<container-ip>` remains reachable over plain SSH via your GitHub key. `ansible@<tailscale-hostname>` (printed by the final task, and now in `inventory.yaml`) becomes reachable once Tailscale SSH is up (`tailscale ssh`, or plain `ssh` once you've configured Tailscale SSH policy).

**Note:** step 9 rewrites the whole file from parsed YAML data (`sort_keys=False` to preserve group/key order), so blank-line spacing between top-level groups doesn't survive the first run — the data and structure are unaffected, it's purely cosmetic.

## Usage

```bash
make help        # list all targets
make install      # pip install -r requirements.txt
make lint         # ansible-lint
make syntax       # syntax-check all playbooks
make check        # dry run (--check --diff) all playbooks
make run          # apply all playbooks for real
```

## Conventions

- Roles stay narrowly scoped to what they run against (e.g. `lxc_prepare` on the PVE host, `lxc_bootstrap` on the container itself); playbooks stay a thin `hosts:` + `roles:` declaration per play.
- Role variables are prefixed with the role name (e.g. `pve_host_*`) per `ansible-lint`'s `var-naming[no-role-prefix]` rule.
- Templated managed files (`templates/*.j2`) carry the standard `{{ ansible_managed | comment }}` header instead of hand-written comments, so drift from out-of-band changes (e.g. someone running the upstream script manually) is detected and corrected on the next run. Plain `files/*` used with the `script` module (which doesn't render Jinja) use a static header comment instead.
- FQCN module names (`ansible.builtin.*`) throughout.
- `ansible-lint` (pinned in `requirements.txt`) must pass at the `production` profile.
