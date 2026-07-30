# Ansible Setup Guide

## Virtual Environment Setup (One-Time)

The Ansible playbooks require a Python virtual environment with dependencies installed.

### Step 1: Create Virtual Environment

```bash
cd ansible
python3 -m venv .venv
```

This creates a `.venv/` directory containing an isolated Python environment for this project.

### Step 2: Install Dependencies

```bash
source .venv/bin/activate
pip install -r requirements.txt
```

The `requirements.txt` includes:
- **ansible-core**: Orchestration engine
- **ansible-lint**: Playbook linting and validation
- **molecule + molecule-docker**: Testing framework for roles

Interactive selection menus use bash built-ins (`read`) and don't require additional Python packages.

### Step 3: Verify Installation

```bash
which ansible              # Should show path in .venv/bin
ansible --version         # Verify ansible is available
ansible-lint              # Verify linting works
```

## Running Playbooks (Each Session)

**Important**: The virtual environment **must be active** before running any Ansible playbook. It provides Ansible, ansible-lint, and Molecule - all required for bootstrap playbooks and testing.

```bash
cd ansible
source .venv/bin/activate
```

Then run playbooks. For interactive prompts, the terminal must accept input:

```bash
# Interactive LXC bootstrap with numbered menu selection for Proxmox hosts and SSH keys
ansible-playbook playbooks/local-bootstrap-lxc.yaml

# Steady-state workload deployment
ansible-playbook playbooks/workloads.yaml

# Check syntax without running
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check

# Dry-run to preview changes
ansible-playbook playbooks/workloads.yaml --check --diff
```

### Shell Integration (Optional: Auto-activate venv)

Add to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.) to auto-activate the venv when entering the ansible directory:

```bash
# cd hook: auto-activate virtual environment
cd() {
  builtin cd "$@"
  if [[ -d .venv && ! "${VIRTUAL_ENV}" =~ "infrastructure/ansible" ]] && [[ "$PWD" =~ "infrastructure/ansible" ]]; then
    source .venv/bin/activate
  fi
}
```

Or use [direnv](https://direnv.net/) for a simpler approach:

```bash
echo 'layout python .venv' > .envrc
direnv allow
```

## Interactive Prompts

When running `local-bootstrap-lxc.yaml`, you'll see interactive menus. **Always respond with a number** matching the option you want:

### Proxmox Host Selection

```
Select Proxmox host:
1) caba-host
2) gateway-host
Enter number
```

**Type `1` and press Enter** to select caba-host (the actual Proxmox hypervisor with storage).

(Tip: If you just press Enter without typing, it defaults to 1)

### SSH Key Selection
```
Select SSH public key:
1) id_rsa.pub
2) id_ed25519.pub
Enter number
```

**Type the number** (1 or 2) of the key you want to use for the container's root SSH access.

### Other Prompts
For most other prompts (container ID, hostname, CPU cores, memory, etc.), **just press Enter to accept the suggested default value.

## Deactivating Virtual Environment

When done, deactivate the environment:

```bash
deactivate
```

## Troubleshooting

### Playbook Tests

#### "command not found: ansible"
The venv is not activated. Run:
```bash
cd ansible
source .venv/bin/activate
```

#### Molecule tests fail with "ModuleNotFoundError: requests"

On systems with system-wide Ansible installations, Molecule may use the system Python instead of the venv. Use the venv Python explicitly:

```bash
cd roles/base
../../.venv/bin/python -m molecule test
```

Alternatively, run with `PYTHONPATH` set:
```bash
cd roles/base
PYTHONPATH="../../.venv/lib/python3.14/site-packages" ../../.venv/bin/molecule test
```

### "ImportError" or missing dependencies

Dependencies not installed. Run:
```bash
cd ansible
source .venv/bin/activate
pip install -r requirements.txt
```

### "No such file or directory: .venv"
Virtual environment doesn't exist. Run setup from Step 1 above.

### "CT [ID] already exists on node 'caba-host'"
The container ID you selected (or that was auto-calculated as the next available ID) already exists. Options:
1. **Use a different container ID** - When prompted, type a different number (e.g., 105, 110, etc.)
2. **Delete the existing container** - On caba-host: `pct destroy 102`
3. **Verify you selected caba-host** - When prompted "Select Proxmox host", make sure you type `1` for caba-host (not gateway-host)

The playbook calculates the next available ID by scanning the selected host. If you selected the wrong host, it won't know about containers on the other host

## How Defaults Work

When prompted, you can:

- **Accept the default**: Press Enter without typing anything
  - Example: `LXC container ID (default 105)` → press Enter → container ID becomes `105`
- **Override the default**: Type a value and press Enter
  - Example: `LXC container ID (default 105)` → type `120` → press Enter → container ID becomes `120`

All numeric inputs (CPU cores, memory) are automatically parsed and validated. Hostname validation requires lowercase alphanumeric characters and hyphens.

## Upgrading Dependencies

To update all packages to latest compatible versions:

```bash
cd ansible
source .venv/bin/activate
pip install -U -r requirements.txt
```

## CI/CD and Non-Interactive Mode

In CI/CD pipelines, create the venv and run without interactive prompts by supplying variables:

```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  -e lxc_pve_host=caba-host \
  -e lxc_create_ctid=105 \
  -e lxc_create_hostname=myhost \
  -e lxc_create_ssh_pubkey="$(cat ~/.ssh/id_ed25519.pub)" \
  -e lxc_bootstrap_tailscale_authkey="$TS_AUTHKEY"
```
