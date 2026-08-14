# Ansible

Debian host configuration and Proxmox LXC bootstrap.

## Boundaries

- `roles/base/` is the idempotent Debian baseline: users, sudo, SSH, locale,
  time, console fallback, MOTD, and log retention.
- `roles/tailscale/` installs Tailscale and joins a tailnet only when supplied an
  auth key.
- `roles/deploy/` creates the local GitHub Actions account used over Tailscale SSH.
- `roles/docker/` installs Docker Engine and Compose, and grants configured users Docker access.
- `tasks/lxc_*` and `tasks/pve_host/` are procedural Proxmox workflows. They
  create and prepare infrastructure; they are not steady-state roles.
- `playbooks/workloads.yaml` applies the baseline and inventory-selected roles
  to Debian guests.
- `playbooks/local-*.yaml` are operator-run bootstrap and feature workflows;
  `local` means they run from the LAN rather than the GitHub Actions tailnet.

Roles are composable and inventory-driven. `workloads.yaml` always applies
`base` and `tailscale`, then applies each role named by a host's `host_roles`.

## Supported model

- Debian is the only supported guest operating system.
- Tailscale SSH is the only supported remote access path.
- The Proxmox console is the recovery path during initial bootstrap.
- Docker and privileged LXC features are opt-in.
- Secrets are passed as extra vars or prompts; do not commit them.

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

A workload selects specialized roles with `host_roles`:

```yaml
host_roles: [deploy, docker]
```

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
