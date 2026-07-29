# Ansible

## Ansible Playbook Organization and Principles

This repository utilizes Ansible to manage infrastructure configurations. The organization of playbooks and roles follows these core principles:

*   **Separation of Concerns:**
    *   **Steady-State Configuration:** Defined in reusable Ansible roles (e.g., `roles/base/`, `roles/tailscale/`, `roles/docker/`). These roles encapsulate idempotent configurations that ensure a server reaches and maintains a desired end-state. `base` + `tailscale` are applied to every host in `workloads.yaml`; specialized roles like `docker` are applied only to hosts that declare them via `host_roles` in `inventory.yaml`.
    *   **Bootstrap Process:** Orchestrated by dedicated playbook files (e.g., `playbooks/local-bootstrap-lxc.yaml`). These playbooks handle the initial provisioning of new infrastructure. They include procedural, one-off tasks specific to the setup sequence inline or in task files (e.g., `tasks/lxc_bootstrap/main.yml`, `tasks/lxc_prepare/main.yml`), and call upon Ansible roles for steady-state configurations where applicable.
    *   **Composable Features:** LXC feature tasks (e.g., `tasks/lxc_features/add_docker.yml`, `tasks/lxc_features/add_tailscale.yml`) are modular building blocks that can be orchestrated via standalone playbooks (e.g., `playbooks/local-lxc-add-docker.yaml`, `playbooks/local-lxc-add-tailscale.yaml`) to add capabilities to existing containers without re-running the full bootstrap.

*   **DRY (Don't Repeat Yourself):** Common configurations are defined once in roles and applied consistently across hosts and playbooks.

*   **Modularity and Reusability:** Ansible roles and task includes allow for composing complex configurations from smaller, manageable parts.

*   **Maintainability:** A clear distinction between initial setup and ongoing configuration simplifies updates, troubleshooting, and understanding the infrastructure's desired state.

*   **Idempotency:** Steady-state configurations guarantee predictable outcomes, ensuring that running `workloads.yaml` multiple times will result in the same final configuration without unintended side effects.

All Ansible-managed hosts on the tailnet must have the `tag:ansible` Tailscale tag so the tailnet ACL permits management traffic.

## Developer setup

Work from this directory so Ansible discovers `ansible.cfg`. The configuration selects `inventory.yaml`, disables host-key checking for these managed hosts, and lets Ansible choose the target Python interpreter automatically.

Create an isolated Python environment and install the pinned Ansible tooling:

```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Confirm the active tools and configuration:

```bash
ansible --version
ansible-lint --version
ansible-config dump --only-changed
ansible-inventory --graph
```

Run the linter before submitting changes:

```bash
ansible-lint
```

## Testing

### Molecule Tests for Roles

All three production roles (`base`, `docker`, `tailscale`) include [Molecule](https://molecule.readthedocs.io/) tests for independent validation without touching live infrastructure.

#### Quick Start

With Docker running, from the `ansible/` directory:

```bash
# Full test cycle for each role: create → apply → verify → destroy
molecule test -s base       # Debian baseline (~2-3 min)
molecule test -s docker     # Docker Engine + Compose plugin (~3-4 min)
molecule test -s tailscale  # Tailscale installation (~3-4 min)

# Or, converge and inspect the container
molecule converge -s docker     # Apply and keep running
docker exec -it debian-bookworm bash  # Inspect inside
docker ps                       # Verify Docker is working
exit
molecule destroy -s docker      # Clean up

# Test idempotency (apply twice, second run should change nothing)
molecule idempotent -s base     # Gold standard for Ansible roles
```

#### What Gets Tested

**Base Role** — Debian baseline (users, packages, locale, timezone, SSH, shells)

**Docker Role** — Docker Engine + Compose plugin + group membership for passwordless docker access

**Tailscale Role** — Tailscale installation from official repository + systemd daemon

#### Documentation

For complete testing guide: `TESTING.md`  
For bootstrap task testing strategy: `TESTING-TASKS.md`  
For navigation: `TESTING-INDEX.md`  
For role-specific details: `roles/{role}/molecule/README.md`

###

## Invoking playbooks

Each playbook begins with a short description, its execution constraints, and a concrete invocation. The following examples show the common command-line variations.

Check syntax without executing tasks:

```bash
ansible-playbook playbooks/local-bootstrap-pve.yaml --syntax-check
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check
ansible-playbook playbooks/workloads.yaml --syntax-check
```

Preview changes and display managed-file differences:

```bash
ansible-playbook playbooks/local-bootstrap-pve.yaml --check --diff
```

Preview changes on one inventory host:

```bash
ansible-playbook playbooks/local-bootstrap-pve.yaml \
  --check \
  --diff \
  --limit caba-host
```

Apply the PVE playbook:

```bash
ansible-playbook playbooks/local-bootstrap-pve.yaml
```

### LXC Bootstrap (interactive, creates new container)

Bootstrap a new LXC container with interactive prompts for all inputs:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml
```

This guides you through container creation (name, CPU, memory, storage, SSH key), feature selection (Docker, Tailscale), and Tailscale registration.

### LXC Bootstrap (existing container)

Bootstrap an existing LXC container by passing the PVE host, container ID, and a Tailscale auth key:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  -e skip_creation=true \
  -e lxc_pve_host=caba-host \
  -e lxc_prepare_ctid=105 \
  -e lxc_bootstrap_tailscale_authkey=tskey-...
```

Omit any of the inputs and the playbook prompts for them interactively (the PVE host prompt is a numbered menu built from the `hypervisors` inventory group).

### Add features to existing containers

These playbooks add specific features to already-bootstrapped containers without re-running the full bootstrap:

#### Add Docker support

```bash
ansible-playbook playbooks/local-lxc-add-docker.yaml -e lxc_ctid=105
```

Non-interactive (supply PVE host):

```bash
ansible-playbook playbooks/local-lxc-add-docker.yaml \
  -e lxc_pve_host=caba-host \
  -e lxc_ctid=105
```

Adds Docker-required LXC feature flags (nesting, keyctl) and reboots the container if needed.

#### Add Tailscale support

```bash
ansible-playbook playbooks/local-lxc-add-tailscale.yaml -e lxc_ctid=105
```

Non-interactive (supply PVE host):

```bash
ansible-playbook playbooks/local-lxc-add-tailscale.yaml \
  -e lxc_pve_host=caba-host \
  -e lxc_ctid=105
```

Tailscale requires a TUN/TAP device to create virtual network interfaces for the VPN tunnel. This playbook adds that support and reboots the container if necessary.

### Steady-state management

Once bootstrapped, containers manage themselves via `workloads.yaml`:

```bash
ansible-playbook playbooks/workloads.yaml
```

Increase verbosity when diagnosing task or connection failures:

```bash
ansible-playbook playbooks/local-bootstrap-pve.yaml -v
ansible-playbook playbooks/local-bootstrap-pve.yaml -vvv
```

## Specialized roles per host

`workloads.yaml` applies `base` + `tailscale` to every host, then loops
over each host's `host_roles` list (declared in `inventory.yaml`) to apply
anything beyond the baseline:

```yaml
# inventory.yaml
workloads:
  hosts:
    traefik-lxc.tortoise-noodlefish.ts.net:
      host_roles: [docker]
```

To add a specialized role to a host, edit `inventory.yaml` only - never
`workloads.yaml`. Check what a host will actually run:

```bash
ansible-inventory --host traefik-lxc.tortoise-noodlefish.ts.net
```
