# Ansible

Debian host configuration and Proxmox LXC bootstrap.

## Boundaries

- `roles/base/` is the idempotent Debian baseline: users, sudo, SSH, locale,
  time, console fallback, MOTD, log retention, and Vector journald shipping.
- `roles/tailscale/` installs Tailscale and joins a tailnet only when supplied an
  auth key.
- `roles/deploy/` creates the local GitHub Actions account used over Tailscale SSH.
- `roles/docker/` installs Docker Engine and Compose, grants configured users
  Docker access, and adds Docker container log shipping to Vector.
- `roles/c5e_reconciler/` installs the c5e controller as a systemd-managed
  Docker container on its dedicated host.
- `tasks/lxc_*` and `tasks/pve_host/` are procedural Proxmox workflows. They
  create and prepare infrastructure; they are not steady-state roles.
- `playbooks/workloads.yaml` converges the baseline and explicit inventory-selected
  capabilities on Debian guests.
- `playbooks/local-bootstrap-lxc.yaml` creates or prepares a guest on the selected
  Proxmox node, bootstraps its management access, and registers it in inventory.
- `playbooks/local-lxc-add-*.yaml` applies narrow Proxmox feature changes to an
  existing guest; `local-bootstrap-pve.yaml` configures hypervisors.
- `local` means these operator-run workflows execute from the LAN rather than
  the GitHub Actions tailnet.

`workloads.yaml` applies `base` and `tailscale` to all workloads, then invokes
only the optional capabilities allowed by `host_roles`.

## Supported model

- Debian is the supported guest operating system for the full baseline. The
  Vector installation also accepts Ubuntu so existing Ubuntu workloads can ship
  journald logs; this does not imply full Ubuntu support for the baseline.
- Tailscale SSH is the only supported remote access path.
- The Proxmox console is the recovery path during initial bootstrap.
- Docker and privileged LXC features are opt-in.
- Follow the VM service credential SOP below for service credentials. Never
  commit values or put them in inventory or command-line arguments.

## VM service credential SOP

Use this procedure for long-lived credentials consumed by systemd-managed
services on any Ansible-managed VM. Keep each service on its own least-privilege
credential where practical.

1. **Source:** for c5e, `C5E_OP_CREDENTIALS` is the raw 1Password
   service-account token passed to `op` as `OP_SERVICE_ACCOUNT_TOKEN`; it is
   not an `op://` item reference. Existing Crow deployments inject a token
   from the `ONE_PASSWORD_SA_TOKEN` secret. Retrieve the raw value from its
   approved secure source; if no copy is available, reissue the token and
   update the Crow secret. Give it read access only to the vaults referenced
   by this host's assigned templates; use a dedicated account if the shared
   Crow token has broader access than c5e needs.
2. **Bootstrap:** use the service-specific targeted Ansible playbook and its
   private `vars_prompt`. Never pass the value through `-e`, command arguments,
   shell environment assignments, or repository files. Generic workload runs
   should skip an uninitialized service rather than prompt or fail.
3. **Store and verify:** write to `/etc/<service>/<service>.env` under a
   root-owned mode-`0700` directory; the file is `root:root` mode `0600`.
   Ansible tasks use `no_log: true` and `diff: false`; systemd reads the file
   with `EnvironmentFile`. Verify file metadata with `stat` and service status
   with `systemctl is-active`/`journalctl`; never print or `cat` the file.
4. **Rotate:** issue a replacement in the source manager, update any Crow
   secret using the same token, and rerun the targeted playbook with the new
   value. Verify the service and secret access before revoking the old token.
   Keep values out of shell history and logs.

## LXC guest storage convention

The LXC bootstrap workflow provisions one host-backed storage mount for
Docker-enabled guests and persistent guest data:

```text
Proxmox host:  /primary/guest-volumes/<guest-hostname>
LXC:          /srv/guest-volumes
Docker root:  /srv/guest-volumes/docker
```

The PVE host configuration owns the shared `/primary/guest-volumes` root
under the host's `/primary` storage directory. It sets that directory to
`nfs_user:nfs_shares` with mode `0755` (without recursively changing existing
contents). The Proxmox/LXC bootstrap workflow owns creation of the
per-guest host directory and the LXC mount at `mp0`; each new guest directory
inherits the root's numeric UID/GID. `mp0` is reserved for this guest-volume
mount, so existing LXC mounts are shifted to `mp1`, `mp2`, and so on when the
convention is applied. The steady-state Docker role owns configuring Docker's
`data-root` to the mounted guest path. Compose stacks should continue to use
normal Docker named volumes; Docker will create their directories below the
configured data root without per-stack host provisioning. Set
`docker_configure_data_root: true` only after the guest volume mount has been
provisioned.

The bootstrap defaults are `/primary/guest-volumes` on the Proxmox host and
`/srv/guest-volumes` in the guest; override them with
`lxc_guest_volume_host_root` and `lxc_guest_volume_guest_root` when needed.
For an existing LXC, run the local bootstrap workflow from the LAN with the
real Proxmox host and CTID, review any existing mount points, and preserve
`mp0` as the guest-volume mount. The workflow refuses to replace a conflicting
existing `mp0`. Docker data-root configuration is intended for newly
provisioned guests; existing Docker data under `/var/lib/docker` is outside
the scope of this bootstrap automation.

This convention applies to LXC guests. VMs cannot consume a Proxmox host
bind mount directly. `docker-vm-dmz` therefore intentionally keeps Docker's
storage in the VM at `/var/lib/docker`; it must be protected by whole-VM
backups or a separate offsite backup job. If VM storage requirements change,
provision a dedicated virtual disk and mount it in the VM at
`/srv/guest-volumes` rather than treating the VM like an LXC.

The current guest layout is:

| Guest | Type | Guest-volume mount | Docker root |
| --- | --- | --- | --- |
| `jellyfin-lxc` | LXC | `/srv/guest-volumes` | Not a Docker host |
| `traefik-lxc` | LXC | `/srv/guest-volumes` | `/var/lib/docker` |
| `docker0-lxc` | LXC | `/srv/guest-volumes` | `/srv/guest-volumes/docker` |
| `docker-vm-dmz` | VM | None | `/var/lib/docker` |

A guest-volume mount and Docker data-root configuration are separate
operations. Adding the mount does not migrate or relocate existing Docker
data; that remains outside the bootstrap automation.

## Setup

```bash
cd ansible
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Use the project interpreter for every command:

```bash
.venv/bin/ansible-playbook playbooks/workloads.yaml
```

## Inventory

`inventory.yaml` contains two operational groups:

- `workloads`: Debian guests reached over Tailscale SSH.
- `hypervisors`: Proxmox hosts configured by the local PVE playbook.

Each workload's `host_roles` is a duplicate-free list of optional capabilities.
`workloads.yaml` applies `base` and `tailscale` to every workload, then explicitly
selects only these roles: `deploy`, `docker`, and `c5e_reconciler`. Unknown or
duplicate entries fail validation before any role runs. `deploy` identifies
GitHub Actions deployment hosts; `c5e_reconciler` permits application assignments
that c5e reconciles but never adds that host to GitHub Actions deployment
discovery.

```yaml
host_roles: [docker, c5e_reconciler]
```

## c5e controller

`lxc-docker-core0` is configured with `docker` and `c5e_reconciler`, but not
`deploy`. Its application stack assignments remain eligible for preflight and
are reconciled by c5e; Compose deployment workflows continue to discover only
hosts with `deploy`. The platform workflow therefore no longer targets this
host, while remaining unchanged for other deploy hosts.

Install or rotate the controller credential with the targeted playbook:

```bash
.venv/bin/ansible-playbook playbooks/c5e-reconciler.yaml
```

Merge the c5e controller change and wait for `forgejo.weinbender.io/labs/c5e:main`
to be published before applying this playbook. It prompts privately for the
service-account credential and, if the existing `proxy` network needs explicit
approval, its exact network and daemon IDs. The role pulls the image, writes the
credential to root-only `/etc/c5e-reconciler/c5e.env`, removes any existing
container with the c5e Compose project/service labels, and starts the systemd
unit. It leaves the old Compose directory and all named volumes in place.

Until the targeted playbook installs this credential file, generic
`playbooks/workloads.yaml` runs skip the c5e role rather than failing. Once the
file exists, those runs manage the systemd unit normally.

The systemd unit uses host networking, keeps `/var/lib/c5e-live`, and mounts the
named volume `c5e_reconciler_state` at `/var/lib/c5e-state`. Docker reuses that
volume if present or creates an empty one if absent; no state/data migration is
performed. The Docker socket grants host-root-equivalent access.

The dashboard listens on `127.0.0.1:8080`; no external Traefik route is
configured. The controller itself is not attached to `proxy`, so its startup
does not depend on the network it ensures for applications. Existing
application containers with foreign ownership labels may still require a
separate controller ownership transition.

The controller creates `proxy` if it is absent. If it already exists, inspect
the network and daemon IDs:

```bash
docker network inspect proxy --format '{{json .}}'
docker info --format '{{.ID}}'
```

Enter both exact IDs at the playbook prompts to bind the existing local,
attachable bridge. c5e rejects unexpected settings and conflicting project or
owner labels; it never replaces or disconnects the network. Leave both IDs
blank when `proxy` does not exist.

The role removes an old c5e container only when its Compose project and service
labels match. It leaves the old Compose files and state volume; Docker reuses
`c5e_reconciler_state` or creates an empty volume if it is absent.

## Playbooks

```bash
.venv/bin/ansible-playbook playbooks/workloads.yaml
.venv/bin/ansible-playbook playbooks/local-bootstrap-lxc.yaml
.venv/bin/ansible-playbook playbooks/hypervisors.yaml
.venv/bin/ansible-playbook playbooks/local-lxc-add-docker.yaml \
  -e lxc_pve_host=pve -e lxc_ctid=105
.venv/bin/ansible-playbook playbooks/local-lxc-add-tailscale.yaml \
  -e lxc_pve_host=pve -e lxc_ctid=105
```

`local-bootstrap-lxc.yaml` prompts for missing creation, container, and
Tailscale inputs. Existing containers use `-e skip_creation=true`.

## Validation

```bash
.venv/bin/ansible-lint
for playbook in playbooks/*.yaml; do
  .venv/bin/ansible-playbook "$playbook" --syntax-check
done
.venv/bin/ansible-inventory --graph
```

Role tests require Docker and run one suite at a time:

```bash
cd roles/base && ../../.venv/bin/molecule test
cd ../docker && ../../.venv/bin/molecule test
cd ../tailscale && ../../.venv/bin/molecule test
```
