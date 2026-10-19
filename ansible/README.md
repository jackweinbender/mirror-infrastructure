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
- `playbooks/workloads.yaml` applies the baseline and inventory-selected roles
  to Debian guests.
- `playbooks/local-*.yaml` are operator-run bootstrap and feature workflows;
  `local` means they run from the LAN rather than the GitHub Actions tailnet.

Roles are composable and inventory-driven. `workloads.yaml` always applies
`base` and `tailscale`, then applies each role named by a host's `host_roles`.

## Supported model

- Debian is the supported guest operating system for the full baseline. The
  Vector installation also accepts Ubuntu so existing Ubuntu workloads can ship
  journald logs; this does not imply full Ubuntu support for the baseline.
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

A workload selects specialized roles with `host_roles`. `deploy` identifies GitHub Actions deployment hosts; `c5e_reconciler` permits application assignments that are reconciled by c5e but never adds that host to GitHub Actions deployment discovery.

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

For the initial handoff, first merge the c5e CLI change and wait until
`forgejo.weinbender.io/labs/c5e:main` has been rebuilt and published with both
proxy-migration flags. Then run this playbook from the changed infrastructure
checkout before merging/pushing its inventory and role change, so an automatic
`playbooks/workloads.yaml` run cannot precede the credential bootstrap. The role
pulls the image and checks its `--help` output for both migration flags and all
current launch options; a stale image fails before Compose retirement. Ansible
prompts privately for `C5E_OP_CREDENTIALS`; do not pass it in shell arguments or
place it in inventory. The role writes it to the root-owned, mode-`0600`
`/etc/c5e-reconciler/c5e.env` with `no_log`. Regular `playbooks/workloads.yaml`
runs reuse that protected file without prompting.

Before rollout, the exact existing `c5e_reconciler_state` Docker volume must be
present; Ansible inspects it and never creates, removes, or recreates it. When
Compose labels exist, they must match
`com.docker.compose.project=c5e-reconciler` and
`com.docker.compose.volume=c5e_reconciler_state`; conflicting labels fail closed.
If either label is absent and no identity record exists, inspect the volume:

```bash
docker volume inspect c5e_reconciler_state
```

Enter `CONFIRM_C5E_STATE_VOLUME` at the targeted playbook prompt only after
confirming this is the existing controller state volume. Ansible records its
name, driver, mountpoint, creation time, scope, options, and labels in the
root-only `/var/lib/c5e-reconciler/state-volume-identity.json` and rejects later
changes.

If the legacy project directory or any candidate Compose container exists,
Ansible also requires the regular matching marker line
`STACK_NAME=c5e-reconciler` and at least one candidate service container. It
verifies both Docker labels `com.docker.compose.project=c5e-reconciler` and
`com.docker.compose.service=c5e-reconciler` on every candidate; absent or
mismatched evidence aborts before stopping/removing anything. Only verified
service containers are stopped/removed and the exact marked c5e project
directory (including its old runtime `.env`) is removed. Ansible does not run
`docker compose down`, touch other stack directories, or delete any volume.

The role pulls the current `forgejo.weinbender.io/labs/c5e:main` image and
checks its advertised CLI contract before retiring the old service, so a pull
or capability-check failure leaves the Compose controller running. The systemd
unit runs that image with the current repository, host, reconciliation, and
retention flags. It uses host networking and listens for the dashboard only on
`127.0.0.1:8080`; there is deliberately no Traefik route or other externally
reachable dashboard route. The controller is not attached to `proxy`, and
this migration does not remove or disable the existing `proxy` network. Its
Docker socket mount grants host-root-equivalent access.

Persistent controller state reuses the exact existing Docker named volume
`c5e_reconciler_state`, mounted at `/var/lib/c5e-state`; do not rename or remove
it during rollout. `/var/lib/c5e-live` remains mounted at the same path.

The current `docker-networking` definition creates `proxy` as an attachable,
local bridge network. The infrastructure platform workflow can also create it
with the raw fallback `docker network create --driver bridge --attachable
proxy`, which has no `com.docker.compose.project` label. Before adopting the
existing network, inspect its exact ID and the Docker daemon ID:

```bash
docker network inspect proxy --format '{{json .}}'
docker info --format '{{.ID}}'
```

Before production handoff, verify the network is named `proxy`, uses driver
`bridge`, has local scope and `Attachable=true`. A Compose-created legacy
network may carry `com.docker.compose.project=docker-networking`; the raw
fallback may have no project label. Reject any other project label or
conflicting c5e manager/host ownership labels. Enter both exact IDs at the
prompts; each supplied ID must match
`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`. The role passes them as
`--proxy-network-migration-id` and
`--proxy-network-migration-daemon-id`; c5e validates the network/daemon pair
and persists an accepted pair. Keep the role defaults empty and never guess or
hard-code IDs. If inspection does not match, stop rollout and leave the existing
network untouched. c5e's proxy-network ensure is independent of
`--deploy-host=false`; newly created networks must carry c5e manager/host labels.

The retirement removes only `/etc/compose-stacks/c5e-reconciler` after matching
ownership evidence is verified; it leaves the existing `proxy` network intact.

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
