# Base Role Molecule Tests

Test the `base` role independently using [Molecule](https://molecule.readthedocs.io/).

## Overview

Molecule spins up a temporary Debian container, applies the base role, and verifies the configuration. This allows you to validate the role locally without touching live infrastructure.

## Prerequisites

- Docker or Podman running
- Python requirements installed with `molecule` and `molecule-docker`:
  ```bash
  pip install -r ../../requirements.txt
  ```

## Running Tests

From the `ansible/` directory (where this repo's `ansible.cfg` lives):

### Test converge (apply role once)
```bash
molecule converge -s base
```
Applies the role to the test container and keeps it running for inspection.

### Test idempotency (apply role twice)
```bash
molecule idempotent -s base
```
Applies the role twice. The second run should produce no changes—the gold standard for well-written Ansible.

### Full test (create → converge → verify → destroy)
```bash
molecule test -s base
```
Runs the complete test cycle: creates a container, applies the role, verifies the configuration, then tears down.

### List test instances
```bash
molecule list -s base
```

### Debug an instance
```bash
molecule converge -s base
# Container stays running; inspect with docker
docker exec -it debian-bookworm /bin/bash
# Clean up when done:
molecule destroy -s base
```

## What Gets Tested

**Converge** (molecule/default/converge.yml):
- Applies the base role to a fresh Debian Bookworm container

**Verify** (molecule/default/verify.yml):
- Ansible user (`ansible`) exists
- Critical packages installed (openssh-server, sudo, curl, git, vim, etc.)
- Locale configured to `en_US.UTF-8`
- Timezone symlink exists at `/etc/localtime`
- SSH service is running
- Shell assignments are correct (ansible → bash, root → zsh)

## Customization

Edit `molecule/default/molecule.yml` to:
- Change the Debian image version (currently `bookworm`)
- Add more instances to test against
- Configure different driver backends (KVM, Vagrant, etc.)

Edit `molecule/default/verify.yml` to add more post-apply assertions.
