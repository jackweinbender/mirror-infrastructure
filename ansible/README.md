# ansible/

Ansible playbooks and roles for configuring self-hosted infrastructure: LXC/VM hosts reachable over Tailscale, and Proxmox VE hosts on the local LAN.

## Playbooks

| Playbook | Hosts group | Purpose |
|----------|-------------|---------|
| `core.yaml` | `core` | Edge ingress device / webserver config |
| `pve.yaml` | `pve_hosts` | Converges Proxmox VE hosts to desired state via the `pve_host` role |

## Roles

| Role | Purpose |
|------|---------|
| `roles/pve_host/` | Idempotent post-install config for Proxmox VE nodes: disables the enterprise repo, enables the no-subscription repo, patches the Web/Mobile UI subscription nag, disables HA services, and keeps packages up to date. Reimplements the useful parts of community-scripts' `post-pve-install.sh` without the interactive `whiptail` prompts. |

## Running against Proxmox VE hosts (LAN)

`pve_hosts` entries in `inventory.yaml` connect as `root` over raw LAN IPs (e.g. `192.168.1.144`) — not over Tailscale, so this is run from a machine on the same LAN, not from CI.

### Prerequisite: add your SSH key first

On a freshly-installed PVE node you won't have SSH access yet, so Ansible can't connect. Add your public key via the Proxmox web UI's **Datacenter → node → Shell** (noVNC console, already root by default), then paste:

```bash
curl -fsSL https://github.com/<your-github-username>.keys >> ~/.ssh/authorized_keys
```

Repeat for every host in the `pve_hosts` group. Once that's done, confirm you can connect directly (`ssh root@<host-ip>`) before running Ansible.

### Apply

```bash
cd ansible
make check-pve   # dry run (--check --diff)
make run-pve     # apply for real
```

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

- One role per host group under `roles/<name>/`; playbooks stay a thin `hosts:` + `roles:` declaration.
- Role variables are prefixed with the role name (e.g. `pve_host_*`) per `ansible-lint`'s `var-naming[no-role-prefix]` rule.
- All managed file content (`templates/*.j2`) carries the standard `{{ ansible_managed | comment }}` header instead of hand-written comments, so drift from out-of-band changes (e.g. someone running the upstream script manually) is detected and corrected on the next run.
- FQCN module names (`ansible.builtin.*`) throughout.
- `ansible-lint` (pinned in `requirements.txt`) must pass at the `production` profile.
