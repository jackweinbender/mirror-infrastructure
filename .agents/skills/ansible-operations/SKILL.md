---
name: ansible-operations
description: Safely change, validate, and run this repository's Ansible Debian host configuration and Proxmox LXC bootstrap workflows, including inventory roles, Tailscale access, guest-volume mounts, and Docker host setup.
---

# Ansible operations

Use this skill for changes to `ansible/`, host provisioning, workload convergence,
role behavior, inventory selection, or Proxmox LXC bootstrap. Read
`ansible/README.md` and `ansible/AGENTS.md` plus the relevant role or playbook
before editing.

## Choose the correct process

- `playbooks/workloads.yaml` is steady-state, idempotent Debian guest
  configuration. It always applies `base` and `tailscale`, then applies optional
  roles selected by each host's `host_roles` (for example `deploy` and `docker`).
- `tasks/lxc_*` and `tasks/pve_host/` are procedural bootstrap workflows, not
  steady-state roles.
- `playbooks/local-*.yaml` are operator-run workflows from the LAN. Review their
  inventory, limits, tags, prompts, and extra vars before running them; never let
  a local bootstrap accidentally target production workloads.
- Debian guests use Tailscale SSH. The Proxmox console is the recovery path during
  initial bootstrap.

## Guest storage and Docker

For Docker-enabled LXCs, the bootstrap convention is:

```text
Proxmox host: /primary/guest-volumes/<guest-hostname>
LXC:          /srv/guest-volumes
Docker root:  /srv/guest-volumes/docker
```

The bootstrap owns the per-guest host directory and LXC `mp0` mount; `mp0` is
reserved for that mount and existing mounts must be shifted or reviewed. The
steady-state Docker role owns `data-root` configuration. Provision the mount
before setting `docker_configure_data_root: true`; adding a mount does not migrate
existing `/var/lib/docker` data. This convention is for LXCs only. VMs such as
`docker-vm-dmz` retain `/var/lib/docker` and need whole-VM or separate offsite
backups.

Do not automate the LAN gateway DNS A record through Ansible. After a gateway LXC
has a known LAN address, create the required DNS follow-up through the documented
Cloudflare process.

## Secrets and execution safety

- Pass secrets through prompts, extra vars, or the existing CI mechanism. Never
  put secrets in inventory, logs, generated artifacts, or committed files.
- Inspect inventory selection, `--limit`, and tags before every remote-changing
  command.
- Prefer idempotent role changes; keep bootstrap procedures explicit and narrow.
- Use the project virtual environment, not a system Ansible installation.

## Validation

From `ansible/` run:

```bash
.venv/bin/ansible-lint
for playbook in playbooks/*.yaml; do
  .venv/bin/ansible-playbook "$playbook" --syntax-check
 done
.venv/bin/ansible-inventory --graph
```

When Docker is available, run Molecule one role at a time. From the repository
root, also run `git diff --check`. Do not run production/bootstrap playbooks or
make destructive changes without explicit authorization and a reviewed target.
