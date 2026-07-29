# Composable LXC Bootstrap Features

This document describes the composable bootstrap workflow for LXC containers.

## Architecture Overview

The LXC bootstrap system is built as composable modules that can be combined in different ways:

### Core Building Blocks

**Container Creation** (`tasks/lxc_create/main.yml`)
- Creates a new LXC container on Proxmox with specified properties
- Sets up root SSH access for initial management
- Returns container IP for downstream tasks

**Feature Tasks** (`tasks/lxc_features/`)
- `add_docker.yml` — Adds Docker-required LXC feature flags (nesting, keyctl)
- `add_tailscale.yml` — Adds TUN/TAP device for Tailscale VPN tunnel

**Orchestration** (`tasks/lxc_prepare/main.yml`)
- Coordinates feature tasks
- Always adds Tailscale support (required for bootstrap)
- Optionally adds Docker support
- Handles reboots when config changes are applied

**Bootstrap** (`tasks/lxc_bootstrap/main.yml`)
- Creates management user
- Installs and joins Tailscale
- Registers container in inventory

### Playbooks

**Full Workflow** (`playbooks/local-bootstrap-lxc.yaml`)
- Orchestrates creation → prepare → bootstrap in one playbook
- Supports both interactive and non-interactive modes
- Can skip creation step with `-e skip_creation=true`

**Feature Playbooks** (Composable)
- `playbooks/local-lxc-add-docker.yaml` — Add Docker to existing container
- `playbooks/local-lxc-add-tailscale.yaml` — Add Tailscale to existing container

## Usage Patterns

### Pattern 1: Full Interactive Bootstrap (New Container)

Create and bootstrap a new container with interactive prompts:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml
```

You'll be prompted for:
1. PVE host (numbered menu from inventory)
2. Container ID, hostname, CPU, memory, storage, template
3. SSH public key for root
4. Docker support (y/N)
5. Tailscale auth key

### Pattern 2: Bootstrap Existing Container

Skip creation, just prepare and bootstrap an existing container:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  -e skip_creation=true \
  -e lxc_pve_host=caba-host \
  -e lxc_prepare_ctid=105 \
  -e lxc_bootstrap_tailscale_authkey=tskey-...
```

Omit any `-e` variables to be prompted interactively.

### Pattern 3: Non-Interactive CI/CD (Create New)

Fully automated container creation and bootstrap:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  -e lxc_pve_host=caba-host \
  -e lxc_create_ctid=105 \
  -e lxc_create_hostname=myhost \
  -e lxc_create_cores=2 \
  -e lxc_create_memory=2048 \
  -e lxc_create_storage=local-lvm \
  -e lxc_create_template=debian-12-standard \
  -e lxc_create_ssh_pubkey="ssh-rsa ..." \
  -e lxc_bootstrap_tailscale_authkey=tskey-...
```

### Pattern 4: Add Docker Post-Bootstrap

Enable Docker on an existing container:

```bash
# Interactive (prompts for PVE host)
ansible-playbook playbooks/local-lxc-add-docker.yaml -e lxc_ctid=105

# Non-interactive
ansible-playbook playbooks/local-lxc-add-docker.yaml \
  -e lxc_pve_host=caba-host \
  -e lxc_ctid=105
```

The playbook adds the required feature flags and reboots the container if needed.

### Pattern 5: Add Tailscale Post-Bootstrap

Enable Tailscale on an existing container:

```bash
# Interactive (prompts for PVE host)
ansible-playbook playbooks/local-lxc-add-tailscale.yaml -e lxc_ctid=105

# Non-interactive
ansible-playbook playbooks/local-lxc-add-tailscale.yaml \
  -e lxc_pve_host=caba-host \
  -e lxc_ctid=105
```

The playbook adds the TUN/TAP device and reboots the container if needed.

## Design Principles

**Composability**
- Feature tasks are independent modules
- Can be combined via different playbooks
- New feature playbooks are trivial to add

**Always-On Tailscale**
- Every container gets Tailscale support (TUN/TAP device)
- This is the communication backbone for Ansible management
- Costs nothing if Tailscale is never joined (it's just a device)

**Optional Docker**
- Docker feature flags are only added when requested
- These are expensive privileged flags
- Can be added post-bootstrap without re-running full workflow

**Idempotent**
- Feature tasks check for existing state
- Safe to re-run multiple times
- Skip action if already applied

**Interactive & Automated**
- Prompts guide users through decisions
- Can run fully non-interactive for CI/CD
- Mix of both: prompt only for missing values

## Container Lifecycle

1. **Creation** → Proxmox container is provisioned
2. **Preparation** → Tailscale + optional Docker features configured
3. **Bootstrap** → Management user + Tailscale join + inventory registration
4. **Steady-state** → `workloads.yaml` applies roles based on `host_roles`
5. **Feature adds** → Use composable feature playbooks to enhance containers

## Future Feature Extensions

To add a new feature (e.g., GPU passthrough):

1. Create `tasks/lxc_features/add_gpu.yml` with feature logic
2. Create `playbooks/local-lxc-add-gpu.yaml` as a wrapper playbook
3. (Optional) Update `tasks/lxc_prepare/main.yml` if the feature should be part of the main bootstrap

The feature is immediately usable via:
```bash
ansible-playbook playbooks/local-lxc-add-gpu.yaml -e lxc_ctid=105
```
