# Ansible

Debian host configuration and Proxmox LXC bootstrap.

## Boundaries

- `roles/base/` is the idempotent Debian baseline: users, sudo, SSH, locale,
  time, console fallback, MOTD, and log retention.
- `roles/tailscale/` installs Tailscale and joins a tailnet only when supplied an
  auth key.
- `roles/docker/` installs Docker Engine and Compose for hosts that need it.
- `tasks/lxc_*` and `tasks/pve_host/` are procedural Proxmox workflows. They
  create and prepare infrastructure; they are not steady-state roles.
- `playbooks/workloads.yaml` applies the baseline and inventory-selected roles.
- `playbooks/local-*.yaml` are operator-run bootstrap and feature workflows.

Roles are composable and inventory-driven. `workloads.yaml` always applies
`base` and `tailscale`, then applies each role named by a host's `host_roles`.

## Supported model

- Debian is the only supported guest operating system.
- Tailscale SSH is the only supported remote access path.
- The Proxmox console is the recovery path during initial bootstrap.
- Docker and privileged LXC features are opt-in.
- Secrets are passed as extra vars or prompts; do not commit them.

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
- `hypervisors`: Proxmox hosts used by local bootstrap workflows.

A workload selects specialized roles with `host_roles`:

```yaml
host_roles: [docker]
```

## Playbooks

```bash
.venv/bin/ansible-playbook playbooks/workloads.yaml
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
cd roles/base && ../../.venv/bin/molecule test
cd ../docker && ../../.venv/bin/molecule test
cd ../tailscale && ../../.venv/bin/molecule test
```
