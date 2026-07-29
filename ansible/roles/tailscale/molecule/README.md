# Tailscale Role Molecule Tests

Test the `tailscale` role independently using [Molecule](https://molecule.readthedocs.io/).

## Overview

Molecule spins up a temporary Debian container, applies the base role (prerequisite), then applies the tailscale role, and verifies the installation. The test verifies Tailscale installation from the official repository and daemon startup, but does **not** join the tailnet (no authkey in test environment).

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
molecule converge -s tailscale
```
Applies the role to the test container and keeps it running for inspection.

### Test idempotency (apply role twice)
```bash
molecule idempotent -s tailscale
```
Applies the role twice. The second run should produce no changes.

### Full test (create → converge → verify → destroy)
```bash
molecule test -s tailscale
```
Runs the complete test cycle: creates a container, applies both base and tailscale roles, verifies the installation, then tears down.

### Debug an instance
```bash
molecule converge -s tailscale
# Container stays running; inspect with docker
docker exec -it debian-bookworm /bin/bash
# Check tailscale status:
tailscale version
systemctl status tailscaled
# Clean up when done:
molecule destroy -s tailscale
```

## What Gets Tested

**Prerequisites** (base role):
- ansible user exists
- Base packages and configuration

**Tailscale installation**:
- `tailscale` binary installed at `/usr/bin/tailscale`
- `tailscaled` daemon binary installed at `/usr/sbin/tailscaled`
- Tailscale installed from official apt repository
- Tailscale GPG key configured at `/etc/apt/keyrings/tailscale.asc`

**Service status**:
- tailscaled daemon running (systemd)
- tailscaled daemon enabled (systemd)
- tailscale service file exists

**Functionality**:
- `tailscale version` works
- `tailscale help` works
- Package installed via apt

## Important Notes

### No Tailnet Join in Tests
The test does **not** join the tailnet because:
1. No valid authkey available in test environment
2. TUN/TAP device required for VPN may not be available in container
3. Tests should be isolated, not require external services

The role supports optional joining (pass `tailscale_authkey` var), but tests focus on installation.

### Real-World Tailnet Join
To test joining in real deployments, see:
- `playbooks/local-bootstrap-lxc.yaml` - Interactive tailnet join
- `playbooks/local-lxc-add-tailscale.yaml` - Add Tailscale to existing container

## Customization

Edit `molecule/default/molecule.yml` to:
- Change the Debian image version (currently `bookworm`)
- Add more instances to test against (trixie, bullseye, etc.)
- Configure different driver backends

Edit `molecule/default/verify.yml` to add more verification assertions.

## Troubleshooting

### Issue: "tailscale command not found"
The role installs from official repository using apt. Verify:
1. The official Tailscale apt repository is configured
2. The GPG key is installed correctly
3. The package name is correct (should be `tailscale`)

### Issue: "tailscaled daemon not running"
The daemon may take a moment to start. Check logs:
```bash
docker exec -it debian-bookworm journalctl -u tailscaled -n 50
```

### Issue: "Tailscale GPG key not installed"
The role downloads the key from Tailscale's repository. Check:
1. Network connectivity (docker needs to reach pkgs.tailscale.com)
2. `/etc/apt/keyrings` directory exists with correct permissions
3. The Debian release is supported (bookworm, bullseye, trixie, etc.)

### Issue: Slow convergence
Downloading the Tailscale package from apt repository can take a moment, especially if the container hasn't cached package lists. This is normal.
