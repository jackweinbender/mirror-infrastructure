# Docker Role Molecule Tests

Test the `docker` role independently using [Molecule](https://molecule.readthedocs.io/).

## Overview

Molecule spins up a temporary Debian container, applies the base role (prerequisite), then applies the docker role, and verifies the configuration. This tests Docker Engine installation, Compose plugin, and group membership for passwordless docker access.

## Prerequisites

- Docker or Podman running
- Python requirements installed (from `ansible/requirements.txt`):
  ```bash
  cd ansible
  source .venv/bin/activate
  ```

## Running Tests

From the `ansible/` directory:

### Test converge (apply role once)
```bash
molecule converge -s docker
```
Applies the role to the test container and keeps it running for inspection.

### Test idempotency (apply role twice)
```bash
molecule idempotent -s docker
```
Applies the role twice. The second run should produce no changes.

### Full test (create → converge → verify → destroy)
```bash
molecule test -s docker
```
Runs the complete test cycle: creates a container, applies both base and docker roles, verifies the configuration, then tears down.

### Debug an instance
```bash
molecule converge -s docker
# Container stays running; inspect with docker
docker exec -it debian-bookworm /bin/bash
# Inside the container, test docker access:
su - ansible
docker ps
# Clean up when done:
molecule destroy -s docker
```

## What Gets Tested

**Prerequisites** (base role):
- ansible user exists
- jlw user exists (from base_extra_sudo_users)
- Base packages installed

**Docker installation**:
- Docker is installed and running
- Docker Compose plugin installed
- docker group exists
- Official Docker repository is configured

**Group membership**:
- ansible user in docker group
- jlw user (base_extra_sudo_users) in docker group
- Both can run `docker ps` without sudo

**Service status**:
- Docker daemon running
- Docker daemon enabled (systemd)

## Key Concepts

The docker role depends on the base role:
- Reads `base_ansible_user` (defaults to "ansible")
- Reads `base_extra_sudo_users` (defaults to ["jlw"])
- Derives `docker_group_users` from both

The converge playbook applies **both** roles in order (base first, then docker) to simulate real deployment.

## Customization

Edit `molecule/default/molecule.yml` to:
- Change the Debian image version (currently `bookworm`)
- Add more instances to test against (trixie, bullseye, etc.)
- Configure different driver backends

Edit `molecule/default/verify.yml` to add more verification assertions.

## Troubleshooting

### Issue: "docker group not found"
The docker role inherits from the base role. Make sure both are applied in converge.yml.

### Issue: "ansible user not in docker group"
The group membership is applied during docker role's `group.yml` task. Check that base role ran first and created the ansible user.

### Issue: Timeout waiting for Docker to start
Docker daemon may take a moment to start in the container. The tests include a small delay; if it persists, the container logs will show the issue:
```bash
docker logs debian-bookworm
```

### Issue: "docker command not found"
Docker wasn't installed successfully. Check the role's install.yml task and verify the Debian version is supported by the official Docker repository.
