# Homelab Ansible

Minimal, idempotent Ansible setup for Proxmox homelab (LXC containers + VMs).

## Quick Start

### 1. Bootstrap a fresh host

Run once as root on a new host to install python3, create the `jlw` user, and deploy your SSH key:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap.yml -l <hostname> -u root --ask-pass
```

### 2. Full convergence (run from laptop)

```bash
# Full run (all tags)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Selective runs
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags users,ssh
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags docker
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags tailscale
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags lxc
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags vm

# Check mode (dry-run)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff
```

### 3. Individual playbooks

```bash
# Common config only
ansible-playbook -i inventory/hosts.yml playbooks/common.yml

# Docker hosts only
ansible-playbook -i inventory/hosts.yml playbooks/docker.yml

# LXC only
ansible-playbook -i inventory/hosts.yml playbooks/lxc.yml

# VM only
ansible-playbook -i inventory/hosts.yml playbooks/vm.yml
```

## Inventory

Edit `inventory/hosts.yml` to add your hosts:

```yaml
all:
  children:
    lxc:
      hosts:
        pve-lxc-1:
          ansible_host: 10.0.0.10
        pve-lxc-2:
          ansible_host: 10.0.0.11
    vm:
      hosts:
        pve-vm-1:
          ansible_host: 10.0.0.20
    docker-hosts:
      hosts:
        pve-lxc-1:
        pve-vm-1:
```

## Secrets (sops + age)

1. Generate age key: `age-keygen -o age.key`
2. Edit `vars/secrets.yml` with real values
3. Encrypt: `sops --encrypt --age <public-key> vars/secrets.yml > vars/secrets.yml.enc`
4. Add `vars/secrets.yml.enc` to git, keep `vars/secrets.yml` and `age.key` out of git
5. Decrypt for use: `sops --decrypt vars/secrets.yml.enc` (ansible-vault plugin handles this automatically)

Required secrets:
- `vault_tailscale_auth_key`: Tailscale auth key from https://login.tailscale.com/admin/settings/keys

## Tags

| Tag | Purpose |
|-----|---------|
| `users` | User `jlw`, sudo, SSH keys, docker group |
| `ssh` | SSH hardening (no root, no password, key-only, max 3 tries) |
| `tailscale` | Install and configure Tailscale |
| `docker` | Install Docker Engine + compose plugin |
| `hardening` | System hardening (unattended-upgrades, sysctl, etc.) |
| `lxc` | LXC-specific tweaks |
| `vm` | VM-specific tweaks |
| `bootstrap` | One-time fresh host setup |

## Requirements

- Control machine: Linux or macOS with Ansible ≥ 2.15
- `community.general` collection for LXC connection plugin (optional): `ansible-galaxy collection install community.general`
- `sops` + `age` for secrets
- SSH access to targets (root for bootstrap, `jlw` user after)

## Design Principles

- **Idempotent by default**: Every task uses modules; no `shell`/`command` without `creates`/`changed_when`
- **Check-mode safe**: `ansible-playbook --check` shows no changes on second run
- **Flat tasks**: No role abstraction; task files included by playbooks
- **Single repo**: No Galaxy roles, minimal collections
- **Selective runs**: Tags for every major component