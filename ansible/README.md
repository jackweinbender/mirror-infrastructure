# Ansible

## Ansible Playbook Organization and Principles

This repository utilizes Ansible to manage infrastructure configurations. The organization of playbooks and roles follows these core principles:

*   **Separation of Concerns:**
    *   **Steady-State Configuration:** Defined in reusable Ansible roles (e.g., `roles/common/`, `roles/tailscale/`). These roles encapsulate idempotent configurations that ensure a server reaches and maintains a desired end-state. They are applied by playbooks like `workloads.yaml`.
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

Bootstrap an existing LXC container by passing the PVE host and container ID:

```bash
ansible-playbook playbooks/local-bootstrap-lxc.yaml \
  --extra-vars lxc_pve_host=caba-host \
  --extra-vars lxc_prepare_ctid=105
```

Increase verbosity when diagnosing task or connection failures:

```bash
ansible-playbook playbooks/local-bootstrap-pve.yaml -v
ansible-playbook playbooks/local-bootstrap-pve.yaml -vvv
```
