# Ansible

## Ansible Playbook Organization and Principles

This repository utilizes Ansible to manage infrastructure configurations. The organization of playbooks and roles follows these core principles:

*   **Separation of Concerns:**
    *   **Steady-State Configuration:** Defined in reusable Ansible roles (e.g., `roles/base/`, `roles/tailscale/`, `roles/docker/`). These roles encapsulate idempotent configurations that ensure a server reaches and maintains a desired end-state. `base` + `tailscale` are applied to every host in `workloads.yaml`; specialized roles like `docker` are applied only to hosts that declare them via `host_roles` in `inventory.yaml`.
    *   **Bootstrap Process:** Orchestrated by dedicated playbook files (e.g., `playbooks/local-bootstrap-lxc.yaml`). These playbooks handle the initial provisioning of new infrastructure. They include procedural, one-off tasks specific to the setup sequence inline or in task files (e.g., `tasks/lxc_bootstrap/main.yml`, `tasks/lxc_prepare/main.yml`), and call upon Ansible roles for steady-state configurations where applicable.

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

Bootstrap an existing LXC container by passing the PVE host, container ID, and a Tailscale auth key (required - bootstrap's job is to put the container on the tailnet):

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  --extra-vars lxc_pve_host=caba-host \
  --extra-vars lxc_prepare_ctid=105 \
  --extra-vars lxc_bootstrap_tailscale_authkey=tskey-...
```

Omit any of the three and the playbook prompts for it interactively (the PVE host prompt is a numbered menu built from the `hypervisors` inventory group). Once bootstrapped, the container manages itself via `workloads.yaml`:

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

