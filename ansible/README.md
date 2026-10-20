# Ansible

Debian host configuration and Proxmox LXC bootstrap.

## Boundaries

- `roles/host_ops/` configures standard Debian operations: users, sudo, SSH,
  packages, locale, time, console access, and retention.
- `roles/tailscale/` installs Tailscale and joins the tailnet when supplied an
  auth key.
- `roles/logging/` owns Vector installation and both host and container log
  pipelines, including the service lifecycle shared across profiles.
- `roles/containers/` installs Docker and Compose, configures Docker access,
  and applies only host-specific data-root settings.
- `roles/deploy/` installs c5e on each `deployment_hosts` member; c5e is the
  application implementing the deployment capability.
- `roles/secrets/` protects the c5e service-account file; this is its first
  consumer, not general host/LXC secret distribution.
- `playbooks/debian-host-ops.yaml` applies standard host operations and logging
  to `debian_hosts`; `playbooks/stack-hosts.yaml` adds stack capabilities.
- `playbooks/site.yaml` composes both profiles in order for full convergence.
- `tasks/lxc_*` and `tasks/pve_host/` are operator-run procedural workflows.

## Supported model

- Debian is supported for full host operations; Proxmox hypervisors are separate.
- Vector can accept Ubuntu for existing log shippers; that does not imply full Ubuntu support.
- Tailscale SSH is the supported remote access path; the Proxmox console is the
  bootstrap recovery path.
- Stack hosts are an explicit inventory group. Runtime-only stack hosts do not
  automatically receive deployment reconciliation or application assignments.
- Docker data-root configuration remains explicit per host and is only valid
  after its LXC guest-volume mount exists.

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
convention is applied. The steady-state `containers` role owns configuring
Docker's `data-root` to the mounted guest path. Compose stacks should use normal
Docker named volumes; Docker will create their directories below the
configured data root without per-stack host provisioning. Set
`containers_configure_data_root: true` only after the guest volume mount has
been provisioned.

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
.venv/bin/ansible-playbook playbooks/site.yaml
```

## Inventory and profiles

`debian_hosts` is the standard host-operations population. `stack_hosts` adds
Docker/Compose capability; its child `deployment_hosts` group contains all four
current application hosts: `traefik-lxc`, `docker0-lxc`, `docker-vm-dmz`, and
`lxc-docker-core0`. Runtime-only stack hosts, if added later, can remain in
`stack_hosts` without joining `deployment_hosts`. Stack assignments live at
`deployments/<host>/.env.template` and stay in their existing locations.

The stack-host playbook applies Docker/runtime configuration to `stack_hosts`
and `secrets` plus c5e's `deploy` implementation to `deployment_hosts`. Each
deployment host runs its own controller against its local Docker socket and uses
its exact short inventory hostname as the c5e host ID. Docker storage remains
host-specific: only `docker0-lxc` opts into the mounted LXC data-root;
`docker-vm-dmz` remains a VM using `/var/lib/docker`.

Use `site.yaml` for full convergence. The component profiles can be run
independently when the other profile is already configured:

```bash
.venv/bin/ansible-playbook playbooks/debian-host-ops.yaml
.venv/bin/ansible-playbook playbooks/stack-hosts.yaml
```

## Deployment application: c5e

Initialize or rotate c5e on **one deployment host at a time**. Supply an Ansible
limit naming the exact inventory host; the playbook asserts that one host is
selected and prompts afresh for that host's credential and optional local proxy
network migration IDs:

```bash
.venv/bin/ansible-playbook playbooks/c5e-reconciler.yaml \
  --limit traefik-lxc.tortoise-noodlefish.ts.net
```

Repeat separately for each host. Never share service credentials or network/daemon
IDs between hosts. Inspect the network and Docker daemon **on the target host**
before deciding whether to provide migration IDs:

```bash
docker network inspect proxy --format '{{json .}}'
docker info --format '{{.ID}}'
```

The `secrets` role writes the prompted credential to root-only
`/etc/c5e-reconciler/c5e.env`; `deploy` consumes it and manages the systemd unit.
This is c5e's application credential only; general host/LXC secret distribution
is not implemented.

Each deployment host runs exactly one c5e controller with its own host-local
Docker socket and exact short `inventory_hostname_short` as `--host-id`. The
controller's `/var/lib/c5e-live` worktree is mounted from that same absolute
host path, so Docker sees the same published bind-source paths. Its
`c5e_reconciler_state` named volume is local to that host and is retained; no
state/data migration is performed. The Docker socket grants host-root-equivalent
access. c5e does not adopt existing Docker resources merely because project
names match: foreign/mixed ownership labels block operations. Its `retain`
removal policy leaves removed assignments and orphans in place.

The dashboard listens on `127.0.0.1:8080`; no external Traefik route is
configured. The controller uses host networking, not the `proxy` network, so its
startup does not depend on the network it ensures for applications.

An absent `proxy` network is created by c5e. For an existing network, review its
exact network ID and local Docker daemon ID above. Only pass both IDs to approve
the specific host-local migration; c5e can accept the prior `docker-networking`
Compose project label after that exact approval. This does not make migration
automatic: c5e validates expected settings/ownership and leaves the network and
its attachments untouched. Leave both IDs blank when `proxy` does not exist.
The role stores a supplied approval in root-only
`/etc/c5e-reconciler/proxy-network-migration.json`. Routine convergence retains
these host-local IDs so an Ansible run cannot remove the approval before c5e
accepts the migration. After confirming acceptance on that host, clear the
approval and render the service without migration flags:

```bash
.venv/bin/ansible-playbook playbooks/stack-hosts.yaml \
  --limit traefik-lxc.tortoise-noodlefish.ts.net \
  -e deploy_proxy_network_migration_clear=true
```

Do not clear the approval before c5e has accepted the existing network.

## Playbooks

```bash
.venv/bin/ansible-playbook playbooks/site.yaml
.venv/bin/ansible-playbook playbooks/debian-host-ops.yaml
.venv/bin/ansible-playbook playbooks/stack-hosts.yaml
.venv/bin/ansible-playbook playbooks/local-bootstrap-lxc.yaml
.venv/bin/ansible-playbook playbooks/local-bootstrap-pve.yaml
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
cd roles/host_ops && ../../.venv/bin/molecule test
cd ../containers && ../../.venv/bin/molecule test
cd ../deploy && ../../.venv/bin/molecule test
cd ../tailscale && ../../.venv/bin/molecule test
```
