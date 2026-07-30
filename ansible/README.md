# Ansible

Infrastructure management and bootstrap orchestration using Ansible roles and playbooks.

## Directory Structure

| Path | Purpose |
|------|---------|
| `roles/base/` | Debian baseline: packages, users, SSH, locale, timezone, autologin, logs |
| `roles/docker/` | Docker Engine + Compose + group membership for passwordless docker |
| `roles/tailscale/` | Tailscale VPN client installation and tailnet join |
| `tasks/lxc_*/` | One-shot LXC bootstrap and feature provisioning |
| `tasks/pve_host/` | Proxmox hypervisor configuration |
| `playbooks/workloads.yaml` | Steady-state: applies roles to all managed hosts |
| `playbooks/local-bootstrap-*.yaml` | One-shot bootstrap workflows |

## Design Principles

- **Separation of Concerns**: Steady-state roles (idempotent) vs. bootstrap tasks (procedural)
- **DRY**: Shared configuration lives once in roles; playbooks orchestrate without duplication
- **Composability**: Feature tasks (`lxc_features/`) are modules; playbooks compose them
- **Inventory-Driven**: `workloads.yaml` is generic; per-host specialization via `host_roles` in inventory
- **Idempotency**: Safe to replay; roles check state before making changes
- **Debian-Only**: No Ubuntu/distro detection; treats non-Debian as infrastructure error

## Setup

### Initial Setup (One-Time)

```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ansible-lint                           # Syntax + style check
ansible-inventory --graph               # Verify inventory
```

### Activate for Each Session

```bash
cd ansible
source .venv/bin/activate
# Now run playbooks
ansible-playbook playbooks/local-bootstrap-lxc.yaml
```

### Shell Integration (Optional: Auto-activate venv)

Add to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
# Auto-activate Ansible venv when entering the ansible directory
cd /path/to/infrastructure/ansible && source .venv/bin/activate
```

Or use direnv for automatic activation:

```bash
echo 'layout python .venv' > .envrc
direnv allow
```

**Critical Note**: The virtual environment **must be active** before running any playbooks. It provides Ansible, ansible-lint, and Molecule - all required for bootstrap playbooks and testing.

## Testing

### Playbook Validation
Bootstrap tasks (`tasks/lxc_*`) can't be easily unit-tested (they require Proxmox) but are validated via:
- Syntax check: `ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check`
- Linting: `ansible-lint playbooks/local-bootstrap-lxc.yaml`
- Dry-run: `ansible-playbook playbooks/workloads.yaml --check --diff`

### Role Unit Tests (Molecule)
All production roles have Molecule tests using Docker. **Note**: On systems with a system-wide Ansible installation, ensure the venv Python is used:

```bash
# Explicitly use venv Python for Molecule
.venv/bin/python -m molecule test -s default

# Or within a role:
cd roles/base
../../.venv/bin/python -m molecule test
```

Example tests:
```bash
cd roles/base
../../.venv/bin/molecule test           # Full test (create, converge, verify, destroy)
../../.venv/bin/molecule converge        # Create and converge (stop before destroy)
../../.venv/bin/molecule verify          # Run verify tasks on existing container
../../.venv/bin/molecule destroy         # Clean up Docker container
```

See `roles/{role}/molecule/` for test playbooks and configuration.

## Playbooks

### workloads.yaml (Steady-State)

Apply base + tailscale to every host, then apply each host's `host_roles`:

```bash
ansible-playbook playbooks/workloads.yaml
ansible-playbook playbooks/workloads.yaml --check --diff  # Preview changes
ansible-playbook playbooks/workloads.yaml --limit my-host # Single host
```

To add a role to a host, edit `inventory.yaml` only:

```yaml
workloads:
  hosts:
    my-host.ts.net:
      host_roles: [docker, tailscale]
```

### local-bootstrap-lxc.yaml (One-Shot: New Container)

Create and bootstrap an LXC container with interactive selection menus.

**Interactive (Recommended)**:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml
```

You'll be prompted to:
1. **Create new container?** - Type `y` (or press Enter) for yes, `n` for no
2. **Select Proxmox host** - Interactive numbered menu of available hypervisors
3. **Enter container ID** - Defaults to next available ID on the host (press Enter to accept)
4. **Enter hostname** - Defaults to `lxc-<ctid>` if not provided (press Enter to accept)
5. **Select SSH public key** - Interactive numbered menu of keys in `~/.ssh/*.pub`
6. **CPU cores** - Default 2 cores (press Enter to accept)
7. **Memory in MB** - Default 2048 MB (press Enter to accept)
8. **Container template** - Default `debian-13-standard_13.6-1_amd64` (press Enter to accept)
9. **Enable Docker?** - Type `y` for yes, `n` (or press Enter) for no
10. **Tailscale auth key** - Required to join the tailnet (no default)

**Non-interactive (CI/CD, existing container)**:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  -e skip_creation=true \
  -e lxc_pve_host=caba-host \
  -e lxc_prepare_ctid=105 \
  -e lxc_bootstrap_tailscale_authkey=tskey-...
```

**Non-interactive (CI/CD, create new container)**:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  -e lxc_pve_host=caba-host \
  -e lxc_create_ctid=105 \
  -e lxc_create_hostname=myhost \
  -e lxc_create_cores=2 \
  -e lxc_create_memory=2048 \
  -e lxc_create_storage=local-zfs \
  -e lxc_create_template=debian-13-standard_13.6-1_amd64 \
  -e lxc_create_ssh_pubkey="ssh-rsa ..." \
  -e lxc_bootstrap_tailscale_authkey=tskey-...
```

### local-bootstrap-pve.yaml

Configure a Proxmox hypervisor:

```bash
ansible-playbook playbooks/local-bootstrap-pve.yaml
```

### local-lxc-add-docker.yaml / local-lxc-add-tailscale.yaml

Add features to existing containers after bootstrap:

```bash
ansible-playbook playbooks/local-lxc-add-docker.yaml \
  -e lxc_pve_host=my-proxmox-host \
  -e lxc_ctid=105
```

## Inventory

**Groups:**

- `workloads`: Hosts on the tailnet managed by `workloads.yaml` (Ansible user, SSH over Tailscale)
- `hypervisors`: Proxmox hosts on the LAN managed by bootstrap playbooks (root user, LAN access)

**Per-Host Variables:**

- `host_roles`: List of specialized roles to apply (e.g., `[docker]`). Defaults to `base + tailscale`.

**ACLs:**

All Ansible-managed hosts must have the Tailscale `tag:ansible` tag (required for management ACL).

## Remote Access Model

- **Primary**: Tailscale SSH (`tailscale up --ssh`) over the tailnet
- **Fallback**: Proxmox web console (root login, no password) - see `roles/base/tasks/05-console_logs.yml`
- **No**: Plaintext SSH keys or passwords; only Tailscale SSH

## Role Details

### base (Debian Baseline)

Applies to every host. 5 task files:

| File | Coverage |
|------|----------|
| `01-packages_updates.yml` | Packages, unattended-upgrades, needrestart |
| `02-users_shells.yml` | Create sudoers, set shells |
| `03-ssh_security.yml` | Enforce key-only SSH, regenerate host keys on clones |
| `04-system_time_locale.yml` | Locale, timezone, NTP |
| `05-console_logs.yml` | Root autologin (console fallback), MOTD, log retention |

### docker

Adds Docker Engine + Compose + passwordless docker access if `host_roles: [docker]`. Preflight checks Proxmox LXC flags (nesting, keyctl) and fails fast with clear guidance if not set.

### tailscale

Installs Tailscale. If `tailscale_authkey` is set and host isn't already joined, joins the tailnet with SSH enabled. Applied to every host in `workloads.yaml`.

## Linting & Validation

```bash
ansible-lint                                      # All files
ansible-playbook playbooks/workloads.yaml --syntax-check
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
ansible-playbook playbooks/local-bootstrap-lxc.yaml -vvv  # Verbose debug
```

## Dependencies

- **ansible-core**: Orchestration engine
- **ansible-lint**: Playbook linting and validation
- **molecule + molecule-docker**: Testing framework for roles

All requirements are in `requirements.txt` and installed in the venv. Interactive selection menus use bash built-ins and don't require additional packages.

## Key Decisions

1. **No Feature Flags in Roles**: If a role always does something, it's not gated behind a variable. To skip a task, don't apply that role.
2. **Debian-Only**: No distro detection. Treatment of non-Debian as an infrastructure error (rebuild as Debian).
3. **Idempotency**: Every role is safe to replay multiple times. `workloads.yaml` can run daily or on-demand.
4. **Bootstrap ≠ Steady State**: Bootstrap creates the user and joins tailnet. Everything else (packages, sshd policy, updates, shells) is owned by roles and applied on the first steady-state run.
5. **Inventory-Driven Specialization**: `workloads.yaml` is generic; `host_roles` in inventory drives which roles apply to which hosts. Adding a role to a host means editing inventory only.
6. **Interactive Prompts Over Manual Entry**: Bootstrap playbooks use interactive bash menus for repetitive choices (Proxmox hosts, SSH keys) to reduce typos and improve UX.
