# Testing Ansible Tasks

This document covers testing the `tasks/` directory modules, which are procedural/bootstrap-specific (not steady-state roles).

## Overview

Unlike roles, the tasks directory contains procedural playbooks for bootstrap and provisioning operations:

| Directory | Purpose | Testability |
|-----------|---------|------------|
| `tasks/lxc_bootstrap/` | Initial LXC container setup | ⚠️ Requires SSH, inventory | 
| `tasks/lxc_prepare/` | PVE host-side prep before bootstrap | ⚠️ Requires Proxmox host |
| `tasks/lxc_create/` | LXC container creation | ⚠️ Requires Proxmox host |
| `tasks/lxc_features/` | Add features to existing containers | ⚠️ Requires Proxmox + containers |
| `tasks/pve_host/` | Proxmox host configuration | ⚠️ Requires real Proxmox hosts |

## Why These Are Hard to Test

These tasks are **bootstrap/provisioning** operations that:
1. Make irreversible infrastructure changes (create LXCs, add features)
2. Require external systems (Proxmox, SSH, network devices)
3. Can't be easily isolated in containers
4. Have procedural, one-time-only operations

**This is by design.** Bootstrap runs once; production configuration is handled by roles that Molecule can easily test.

## Testing Strategy

### 1. **Syntax Validation** (CI, No Setup Required)
```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
ansible-playbook playbooks/local-bootstrap-pve.yaml --syntax-check
```
Validates YAML structure before any execution. Catches typos, missing variables, etc.

### 2. **Linting** (CI, No Setup Required)
```bash
ansible-lint
```
Catches common mistakes, deprecated patterns, style issues.

### 3. **Dry-Run on Real Infrastructure** (Manual, Requires Tailscale + Hosts)
```bash
# Preview changes without applying
ansible-playbook playbooks/workloads.yaml --check --diff
```
Shows what would happen without execution. Valuable for catching unintended changes.

### 4. **Unit-Style Testing** (Possible, Limited Value)
Test individual task files in isolation with mock/test inventory. Problem: tasks are highly interdependent and context-dependent.

## What NOT to Test (With Respect to Complexity)

**Don't** try to create Molecule tests for:
- `lxc_create/` - Creates actual LXCs; Docker containers can't simulate Proxmox
- `lxc_prepare/` - Modifies PVE host; requires real Proxmox
- `pve_host/` - Configures hypervisors; not containerizable
- `lxc_bootstrap/` - SSH-based remote execution; requires live container

**Why:** Docker can't simulate Proxmox LXC management, network device creation, or hypervisor-level config. You'd be testing the testing infrastructure, not the actual code.

## What TO Do Instead

### Strategy 1: Test the Underlying Roles (✅ Recommended)
Bootstrap tasks call roles. Test those roles with Molecule:
- `tasks/lxc_bootstrap/main.yml` → calls `roles/base` tasks → **TEST with base role Molecule**
- `playbooks/workloads.yaml` → applies `roles/base`, `roles/docker`, `roles/tailscale` → **TEST with role Molecule tests**

When the roles work in Molecule, the bootstrap tasks that invoke them will work.

### Strategy 2: Syntax + Linting (✅ CI-Integrated)
In your GitHub Actions workflow:
```yaml
- run: ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
- run: ansible-playbook playbooks/local-bootstrap-pve.yaml --syntax-check
- run: ansible-lint
```
Catches errors early, doesn't require infrastructure.

### Strategy 3: Dry-Run Mode (✅ Pre-Execution Validation)
Before running a real bootstrap:
```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml --check --diff -e lxc_pve_host=my-host -e lxc_prepare_ctid=105
```
Shows exactly what will happen. Great for catching issues.

### Strategy 4: Gradual Rollout (✅ Risk Reduction)
1. Bootstrap to **test container** first
2. Verify with `workloads.yaml` dry-run
3. Then bootstrap to **production** with confidence

## Testing The Bootstrap Flow

### End-to-End: Bootstrap → Converge → Verify

When you have a Proxmox host + spare container ID:

```bash
# 1. Syntax check bootstrap playbook
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check

# 2. Preview what bootstrap will do
ansible-playbook playbooks/local-bootstrap-lxc.yaml --check --diff \
  -e lxc_pve_host=your-proxmox-host \
  -e lxc_prepare_ctid=105

# 3. Actually bootstrap (creates container, joins tailnet, etc.)
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  -e lxc_pve_host=your-proxmox-host \
  -e lxc_prepare_ctid=105 \
  -e lxc_bootstrap_tailscale_authkey=tskey-...

# 4. Once bootstrapped, test with role-level Molecule to ensure roles work:
molecule test -s base
molecule test -s docker
molecule test -s tailscale

# 5. Then from CI/cron, workloads.yaml converges the real host:
ansible-playbook playbooks/workloads.yaml
```

## Current Testing Infrastructure

Your existing testing covers:

| Test | What | Where | When |
|------|------|-------|------|
| Syntax check | All playbooks | CI (Optional) | Pre-push |
| Linting | All YAML | CI Main → `ansible-lint` | Every push |
| Role testing | base, docker, tailscale | Local via Molecule | Developer machine |
| Integration | workloads.yaml | CI Main → Real host | Every push to main |

## Example: Testing a Bootstrap Change

You edit `tasks/lxc_bootstrap/main.yml`:

1. **Syntax check** (catches YAML errors):
   ```bash
   ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
   ```

2. **Lint** (catches mistakes):
   ```bash
   ansible-lint
   ```

3. **Test underlying roles** (if you modified a role):
   ```bash
   molecule test -s base
   ```

4. **Dry-run on real infrastructure** (preview changes):
   ```bash
   ansible-playbook playbooks/local-bootstrap-lxc.yaml --check --diff \
     -e lxc_pve_host=test-host -e lxc_prepare_ctid=999
   ```

5. **Bootstrap to test container** (real execution):
   ```bash
   ansible-playbook playbooks/local-bootstrap-lxc.yaml \
     -e lxc_pve_host=test-host \
     -e lxc_prepare_ctid=999 \
     -e lxc_bootstrap_tailscale_authkey=tskey-test
   ```

6. **Verify with roles** (test the result):
   ```bash
   molecule test -s base  # On the bootstrapped host
   ```

7. **Push** (with confidence):
   ```bash
   git push
   ```

## Files to Add to CI/CD (Optional)

Update `.github/workflows/main-ansible.yaml`:

```yaml
- name: Syntax check bootstrap playbooks
  run: |
    ansible-playbook playbooks/local-bootstrap-pve.yaml --syntax-check
    ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check

- name: Dry-run workloads on real hosts (check mode)
  run: ansible-playbook playbooks/workloads.yaml --check --diff
```

## Summary: Testing Hierarchy

```
Level 1: Syntax Check (Free, Always Run)
  → ansible-playbook --syntax-check
  → Catches YAML errors

Level 2: Linting (Free, CI Running)
  → ansible-lint
  → Catches deprecated patterns, mistakes

Level 3: Role Testing (Free with Docker, Local)
  → molecule test -s base
  → molecule test -s docker
  → molecule test -s tailscale
  → Validates roles in isolation

Level 4: Dry-Run on Infrastructure (Manual, Requires Access)
  → ansible-playbook --check --diff
  → Shows real impact before execution

Level 5: Bootstrap to Test Container (Manual, Requires Proxmox)
  → ansible-playbook local-bootstrap-lxc.yaml
  → Full validation of bootstrap process

Level 6: Production Convergence (CI, Automatic)
  → ansible-playbook playbooks/workloads.yaml (runs on real hosts in CI)
  → Final validation
```

## Key Takeaway

**Bootstrap tasks can't be easily unit-tested like roles.** Instead:
1. ✅ Test the **roles** the bootstrap calls (Molecule)
2. ✅ Use **syntax check + linting** for procedural code
3. ✅ Use **--check --diff** before real execution
4. ✅ Bootstrap to **test infrastructure** first, then production
5. ✅ Rely on **workloads.yaml** convergence for final validation

This gives you confidence without trying to mock Proxmox, which would be fragile and not representative of real behavior.
