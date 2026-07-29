# Testing Your Ansible Roles

This document explains the independent testing setup for your Ansible roles and how to use it during development.

## Overview: Why Molecule?

**Before:** Edit a role → push to `main` → apply to production  
**After:** Edit a role → test locally with Molecule → verify → push with confidence

Molecule spins up temporary **isolated Docker containers** and runs your roles against them, letting you validate everything before it touches real infrastructure.

## What's Set Up

All three production roles have **Molecule testing**:

| Role | Tests | Applies To | Status |
|------|-------|-----------|--------|
| `base` | Installation, packages, locale, timezone, shells, SSH | **Every host** | ✅ Complete |
| `docker` | Engine + Compose plugin, group membership | Docker-capable hosts | ✅ Complete |
| `tailscale` | Installation, daemon status, repository config | **Every host** | ✅ Complete |

These are the steady-state roles. Bootstrap tasks (`tasks/`) use syntax checking and dry-run mode (see `TESTING-TASKS.md`).

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) or Podman running
- Python requirements already installed (done during setup):
  ```bash
  cd ansible
  source .venv/bin/activate
  pip install -r requirements.txt
  ```

## Running Molecule Tests for Each Role

All commands run from the `ansible/` directory with `.venv` activated.

### Base Role

The foundational Debian baseline (users, packages, locale, timezone SSH, shells, updates, motd):

```bash
molecule test -s base              # Full test
molecule converge -s base          # Apply and keep running
molecule idempotent -s base        # Test idempotency
```

See `roles/base/molecule/README.md` for details.

### Docker Role

Docker Engine + Compose plugin + group membership for passwordless docker access:

```bash
molecule test -s docker            # Full test
molecule converge -s docker        # Apply and keep running
molecule idempotent -s docker      # Test idempotency
```

**Note:** Docker role tests apply the base role first (dependency), then docker.

See `roles/docker/molecule/README.md` for details.

### Tailscale Role

Tailscale installation from official repository + daemon configuration:

```bash
molecule test -s tailscale         # Full test
molecule converge -s tailscale     # Apply and keep running
molecule idempotent -s tailscale   # Test idempotency
```

**Note:** Tailscale role tests apply the base role first (dependency), then tailscale. Tests do not join the tailnet (no authkey in test environment).

See `roles/tailscale/molecule/README.md` for details.

---

## General Test Workflows

All commands run from the `ansible/` directory with `.venv` activated.

### 1. Full Test Cycle (Create → Apply → Verify → Destroy)

The most common workflow. Spins up a fresh Debian container, applies the role(s), validates, and tears down:

```bash
molecule test -s base       # Test base role
molecule test -s docker     # Test docker role (includes base)
molecule test -s tailscale  # Test tailscale role (includes base)
```

**Output you'll see:**
```
Create ✓
Converge ✓
Idempotency ✓
Verify ✓
Destroy ✓
```

If all checks pass, the role(s) work correctly.

### 2. Converge (Apply Roles, Keep Container)

Apply the role(s) and keep the container running for inspection:

```bash
molecule converge -s base       # Apply base
molecule converge -s docker     # Apply base + docker
molecule converge -s tailscale  # Apply base + tailscale
```

Now you can inspect the container:

```bash
docker exec -it debian-bookworm bash
# Look around, check packages, configs, etc.
```

When done, clean up:

```bash
molecule destroy -s base
```

### 3. Idempotency Test (Apply Twice)

The gold standard: run a role twice, the second run should change **nothing**:

```bash
molecule idempotent -s base       # Test base idempotency
molecule idempotent -s docker     # Test docker idempotency
molecule idempotent -s tailscale  # Test tailscale idempotency
```

If both runs succeed with zero changes on the second run, your role is truly idempotent.

### 4. Inspect an Instance

Converge first, then use Docker to explore:

```bash
molecule converge -s docker  # Or: base, tailscale, etc.
docker ps                     # See the running container
docker exec -it debian-bookworm bash
# Inspect: cat /etc/locale.gen, docker ps, tailscale version, etc.
molecule destroy -s docker
```

### 5. Debug a Failing Role

If a test fails:

```bash
# Converge to see where it fails
molecule converge -s docker  # Or: base, tailscale
# Read the output for the exact error
# Fix the role in your editor
# Destroy the old container
molecule destroy -s docker
# Try again
molecule converge -s docker
```

## What Gets Tested

### Base Role (`roles/base/molecule/default/verify.yml`)

✅ **User:** `ansible` user exists  
✅ **Packages:** Core packages installed (openssh-server, sudo, curl, git, vim, etc.)  
✅ **Locale:** Configured to `en_US.UTF-8`  
✅ **Timezone:** `/etc/localtime` symlink exists  
✅ **SSH:** Service running and enabled  
✅ **Shells:** Correct default shells (ansible → bash, root → zsh)  

### Docker Role (`roles/docker/molecule/default/verify.yml`)

✅ **Docker installation:** Docker binary, version, and running state  
✅ **Compose plugin:** Docker Compose plugin installed and working  
✅ **docker group:** Group exists and users are members  
✅ **User membership:** ansible user + extra_sudo_users in docker group  
✅ **Passwordless access:** Users can run docker commands without sudo  
✅ **Official repo:** Docker apt repository configured  
✅ **Service:** Docker daemon running and enabled  

### Tailscale Role (`roles/tailscale/molecule/default/verify.yml`)

✅ **Tailscale binary:** `/usr/bin/tailscale` installed and executable  
✅ **tailscaled daemon:** `/usr/sbin/tailscaled` installed  
✅ **Systemd service:** Service file exists and is enabled  
✅ **Daemon running:** tailscaled process active  
✅ **Official repo:** Tailscale apt repository configured  
✅ **GPG key:** Tailscale's signing key installed  
✅ **Commands working:** `tailscale version`, `tailscale help` functional  
✅ **Package installed:** Via apt, verifiable with package manager  

To add more checks, edit the `verify.yml` file in each role's `molecule/default/` directory.

## Molecule Files Explained

```
roles/base/molecule/
├── default/
│   ├── molecule.yml      # Configuration (Docker image, volumes, etc.)
│   ├── converge.yml      # Applies your role
│   └── verify.yml        # Tests after applying
└── README.md             # Detailed documentation
```

### `molecule.yml`
- **driver:** Uses Docker (could be KVM, Vagrant, etc.)
- **platforms:** Debian Bookworm (can add more versions)
- **privileged & cgroup:** Allows systemd to run (needed for some base role tasks)

### `converge.yml`
Simply includes and applies your role to the test instance.

### `verify.yml`
Assertions that validate the role did what it should (user exists, packages installed, etc.). Add more tests here as your role grows.

## Adding Tests for Custom Roles

If you create additional roles (beyond base, docker, tailscale), the pattern is identical:

```bash
# From ansible/ directory:
mkdir -p roles/my-role/molecule/default

cd roles/my-role/molecule/default
# Copy from another role and customize:
cp ../../base/molecule/default/molecule.yml .
cp ../../base/molecule/default/converge.yml .
cp ../../base/molecule/default/verify.yml .
```

Then:
1. Edit `converge.yml` to include your new role
2. Edit `verify.yml` to test your role's configuration
3. Run: `molecule test -s my-role`

## Common Issues

### Issue: "Docker daemon is not running"
**Fix:** Start Docker Desktop or enable Podman support in `molecule.yml`

### Issue: "Role dependency failed" when testing docker/tailscale
**Fix:** These roles depend on the base role. The test playbooks include both automatically. If you see a dependency error, verify the base role test works first:
```bash
molecule test -s base
```

### Issue: "Module not found" errors during verify
**Fix:** Collections are in `requirements.txt`. Reinstall if needed:
```bash
source .venv/bin/activate
pip install -r requirements.txt
```

### Issue: Container exits unexpectedly
**Fix:** Check the container logs:
```bash
docker logs debian-bookworm
```

### Issue: Idempotency test fails (second run changes something)
**Fix:** This is a real issue—your role isn't idempotent. Common culprits:
- Task missing `changed_when: false` on commands that don't modify state
- User/group creation without proper idempotency guards
- Template not using conditional updates

Edit the failing task to fix it, then re-test.

### Issue: "Package not found" when testing docker or tailscale
**Fix:** The container needs to update apt cache. The roles include this, but if packages are very new, try:
```bash
molecule converge -s docker -vv  # See verbose output
# Check the container:
docker exec -it debian-bookworm apt update
```

## CI/CD Integration

You can add Molecule tests to your GitHub Actions workflows to catch issues before applying to production.

### Option 1: Add to Existing Ansible Workflow

Update `.github/workflows/main-ansible.yaml`:

```yaml
- name: Test roles with Molecule
  run: |
    molecule test -s base
    molecule test -s docker
    molecule test -s tailscale
```

This runs after syntax check + lint.

### Option 2: Separate Test Workflow

Create `.github/workflows/ansible-test-roles.yml`:

```yaml
name: Test Ansible Roles

on:
  push:
    paths:
      - ansible/**
  pull_request:
    paths:
      - ansible/**

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.14'
          cache: pip
          cache-dependency-path: ansible/requirements.txt
      - name: Install dependencies
        run: pip install -r ansible/requirements.txt
      - name: Test base role
        run: cd ansible && molecule test -s base
      - name: Test docker role
        run: cd ansible && molecule test -s docker
      - name: Test tailscale role
        run: cd ansible && molecule test -s tailscale
```

This provides dedicated test feedback on every PR.

## Testing Bootstrap Tasks

The `tasks/` directory (lxc_bootstrap, lxc_prepare, etc.) are procedural/one-time operations that can't be easily Molecule-tested because they:
1. Make irreversible infrastructure changes
2. Require external systems (Proxmox, network devices)
3. Have one-time-only operations

**Instead,** test these with:
- Syntax checking: `ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check`
- Linting: `ansible-lint`
- Dry-run on real infrastructure: `ansible-playbook playbooks/local-bootstrap-lxc.yaml --check --diff`

See `TESTING-TASKS.md` for comprehensive bootstrap testing strategy.

## Next Steps

1. **Run all role tests locally:** 
   ```bash
   molecule test -s base
   molecule test -s docker
   molecule test -s tailscale
   ```
   (with Docker running)

2. **Edit and iterate:**
   - Modify a role
   - `molecule converge -s role-name`
   - Inspect: `docker exec -it debian-bookworm bash`
   - `molecule destroy -s role-name`

3. **Extend verification:** Add more assertions to `verify.yml` files

4. **Integrate into CI/CD:** Add Molecule tests to GitHub Actions (see CI/CD Integration section above)

5. **Test bootstrap operations:** Use syntax checking + dry-run for tasks/ (see TESTING-TASKS.md)

---

For more info:
- [Molecule documentation](https://molecule.readthedocs.io/)
- `roles/base/molecule/README.md` — Base role tests
- `roles/docker/molecule/README.md` — Docker role tests
- `roles/tailscale/molecule/README.md` — Tailscale role tests
- `TESTING-TASKS.md` — Bootstrap taskfile.
