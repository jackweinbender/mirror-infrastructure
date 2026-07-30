# Testing Ansible Infrastructure

Comprehensive testing guide for playbooks and roles.

## Quick Start

```bash
# Activate venv (required before all commands)
cd ansible
source .venv/bin/activate

# Syntax validation
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check

# Full linting
ansible-lint

# Test a playbook (dry-run, no changes)
ansible-playbook playbooks/workloads.yaml --check --diff
```

## Playbook Testing

### Bootstrap Playbook (`local-bootstrap-lxc.yaml`)

**Status**: ✅ All syntax checks and linting pass

**Validation Steps**:

1. **Syntax check**:
   ```bash
   ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
   ```
   ✅ Passes (ignores `lxc_new` host pattern - it's created at runtime)

2. **Lint check**:
   ```bash
   ansible-lint playbooks/local-bootstrap-lxc.yaml
   ```
   ✅ Passes (0 warnings/errors in 7 files)

3. **Input collection play** (tests interactive prompts):
   ```bash
   # Pre-populate variables to skip interactive prompts
   ansible-playbook playbooks/local-bootstrap-lxc.yaml \
     -e skip_creation=true \
     -e lxc_pve_host=caba-host \
     -e lxc_prepare_ctid=102 \
     -e lxc_prepare_enable_docker=false \
     -e lxc_bootstrap_tailscale_authkey=test \
     --tags "never"
   ```
   ✅ Should show all plays run successfully (skips actual creation/bootstrap)

### Workloads Playbook (`workloads.yaml`)

**Test with dry-run** (no changes made):

```bash
# Preview what workloads.yaml would change
ansible-playbook playbooks/workloads.yaml --check --diff

# Verbose preview
ansible-playbook playbooks/workloads.yaml --check --diff -vv
```

### Variable Resolution Test

Tests that bootstrap play can load base role defaults (required for user creation):

```bash
# Create a test playbook that mimics bootstrap variable loading
ansible-playbook -e "
{
  'base_ansible_user': 'ansible',
  'base_extra_sudo_users': ['jlw'],
  'base_user_shells': {
    'ansible': '/bin/bash',
    'jlw': '/usr/bin/zsh',
    'root': '/usr/bin/zsh'
  }
}
" playbooks/workloads.yaml --check

# Or manually verify base role defaults:
ansible-playbook <<'EOF'
- hosts: localhost
  gather_facts: no
  tasks:
    - include_vars: roles/base/defaults/main.yml
    - debug:
        msg: "base_ansible_user={{ base_ansible_user }}, base_extra_sudo_users={{ base_extra_sudo_users }}"
EOF
```

## Role Testing with Molecule

Molecule tests roles in isolated Docker containers. See `roles/{role}/molecule/` for test configurations.

### Prerequisites

Ensure the venv is active:
```bash
cd ansible
source .venv/bin/activate
```

### Running Role Tests

All roles follow the same test pattern:

```bash
# Test base role
cd roles/base
../../.venv/bin/molecule test

# Test docker role
cd roles/docker
../../.venv/bin/molecule test

# Test tailscale role
cd roles/tailscale
../../.venv/bin/molecule test
```

### Testing Phases

Molecule runs these phases in sequence (stop at any failure):

| Phase | What It Does |
|-------|-------------|
| `dependency` | Install role dependencies (if any) |
| `cleanup` | Clean up from previous runs |
| `destroy` | Destroy test container |
| `syntax` | Check role syntax |
| `create` | Create Docker container |
| `prepare` | Prepare container (install Python, etc.) |
| `converge` | Run role on container (first apply) |
| `idempotence` | Run role again (verify no changes) |
| `side_effect` | Run side-effect tests (if any) |
| `verify` | Run verify tasks (assertions) |
| `cleanup` | Clean up |
| `destroy` | Destroy test container |

### Individual Phases

Run specific phases instead of full test:

```bash
cd roles/base

# Create container and run role, but don't destroy
../../.venv/bin/molecule converge

# Run verify tasks on existing container
../../.venv/bin/molecule verify

# Shell into container
docker exec -it debian-bookworm bash

# Check what's running
../../.venv/bin/molecule list

# Clean up
../../.venv/bin/molecule destroy
```

### Idempotency Test

Verifies role produces no changes on second run (key for steady-state):

```bash
cd roles/base

# Test idempotency explicitly
../../.venv/bin/molecule idempotent
```

### Troubleshooting Molecule

**Problem**: "ModuleNotFoundError: requests"

**Root Cause**: System-wide Ansible installation takes precedence over venv

**Solution**: Explicitly use venv Python:

```bash
cd roles/base
../../.venv/bin/python -m molecule test
```

**Problem**: Docker container won't start

Ensure Docker daemon is running:
```bash
docker ps  # Should list containers without error
```

**Problem**: "KeyError: 'localhost'"

The `localhost` host group doesn't exist. Molecule creates test instances dynamically. Verify `molecule.yml` references correct instance names.

## Test Results Summary

### Playbooks
- ✅ `local-bootstrap-lxc.yaml`: Syntax + lint pass, variable resolution verified
- ✅ `workloads.yaml`: Syntax + lint pass
- ✅ `local-bootstrap-pve.yaml`: Syntax + lint pass
- ✅ `local-lxc-add-docker.yaml`: Syntax + lint pass
- ✅ `local-lxc-add-tailscale.yaml`: Syntax + lint pass

### Roles
- 🔄 `base`: Molecule test setup exists, requires Docker runtime
- 🔄 `docker`: Molecule test setup exists, requires Docker runtime
- 🔄 `tailscale`: Molecule test setup exists, requires Docker runtime

### Bootstrap Tasks
- ✅ `tasks/lxc_create/main.yml`: Syntax pass
- ✅ `tasks/lxc_prepare/main.yml`: Syntax pass
- ✅ `tasks/lxc_bootstrap/main.yml`: Syntax pass, variables verified

## CI/CD Testing

For CI/CD pipelines (GitHub Actions, etc.):

```bash
#!/bin/bash
set -e

cd ansible

# Activate venv
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Validate syntax
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
ansible-playbook playbooks/workloads.yaml --syntax-check

# Lint check
ansible-lint

# Dry-run check (requires connectivity to hypervisors)
# ansible-playbook playbooks/workloads.yaml --check --limit some-test-host

echo "✓ All validation checks passed"
```

## Testing Checklist

Before committing changes to playbooks or roles:

- [ ] Syntax check passes: `ansible-playbook ... --syntax-check`
- [ ] Lint passes: `ansible-lint`
- [ ] No unintended variable changes
- [ ] Role tests pass on Docker: `molecule test`
- [ ] Idempotency passes: `molecule idempotent`
- [ ] No new secrets/credentials hardcoded

## Known Issues & Fixes

### Ansible 2.20.3 Fact Injection Deprecation ✅ FIXED

**Error**: Deprecation warnings about `INJECT_FACTS_AS_VARS`

```
DEPRECATION WARNING: INJECT_FACTS_AS_VARS default to `True` is deprecated, 
top-level facts will not be auto injected after the change. This feature will 
be removed in ansible-core version 2.24.
```

**Root Cause**: Using bare `ansible_FACTNAME` syntax instead of the new `ansible_facts['factname']` syntax

**Fix Applied**:
- `roles/base/tasks/03-ssh_security.yml`: Changed `{{ ansible_date_time.iso8601 }}` → `{{ ansible_facts['date_time']['iso8601'] }}`
- `roles/docker/tasks/preflight.yml`: Changed `{{ ansible_hostname }}` → `{{ ansible_facts['hostname'] }}` (2 occurrences in error messages)
- `roles/tailscale/tasks/main.yml`: Changed `{{ ansible_distribution_release }}` → `{{ ansible_facts['distribution_release'] }}`
- `roles/docker/tasks/install.yml`: Changed `{{ ansible_distribution }}`, `{{ ansible_distribution_release }}`, `{{ ansible_architecture }}` → `{{ ansible_facts['distribution'] }}`, etc.

**Status**: ✅ Fixed - All fact references now use `ansible_facts[]` syntax

**Validation**:
```bash
# No deprecation warnings in syntax check
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
# Returns only expected host pattern warning, no fact injection warnings
```

### Cluster-Wide Container ID Validation ✅ FIXED

**Error**: "VM 106 already exists on node 'gateway-host'" (when creating on 'caba-host')

**Root Cause**: Proxmox uses cluster-wide VMIDs - container IDs must be unique across all nodes, not per-node. The playbook's "next available ID" calculation was only checking the target node.

**Fix Applied**:
- `playbooks/local-bootstrap-lxc.yaml`: Updated to query all nodes with `grep -r 'vmid:' /etc/pve/nodes/` for next available ID
- `tasks/lxc_create/main.yml`: Updated to check cluster-wide before creation attempt
- Both now display clear error if ID exists anywhere in cluster

**Status**: ✅ Fixed in current version

### Other Known Issues

1. **Molecule requires system-side Python management**
   - System-wide Ansible installation may interfere with venv
   - Workaround: Use venv Python explicitly `../../.venv/bin/python -m molecule test`
   - Status: Acceptable - CI/CD runs in isolated environments anyway

2. **`lxc_new` host pattern doesn't exist at parse time**
   - Pattern warning in syntax check is expected
   - Host is created dynamically by `lxc_prepare` tasks
   - Status: Acceptable - playbook execution handles it correctly

3. **Interactive prompts block if not attached to terminal**
   - Bootstrap playbooks use `ansible.builtin.pause` for menus
   - CI/CD must supply variables with `-e` flags instead
   - Status: By design - ensures users see and approve choices

## Testing Goals

1. **Correctness**: Playbooks do what they claim to do
2. **Safety**: No unintended side effects or data loss
3. **Idempotency**: Safe to run multiple times (roles)
4. **Clarity**: Errors are clear and actionable
5. **Coverage**: All code paths have some validation
