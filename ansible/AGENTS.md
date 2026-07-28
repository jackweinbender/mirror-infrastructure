
# AGENTS

This is a sample AGENTS.md file. Replace this with your own content.
The following are the Ansible agents available for use in this repository.

## Ansible Agents

The following table details the available Ansible playbooks and their purposes.

| Playbook Name              | Description                                                                 |
| -------------------------- | --------------------------------------------------------------------------- |
| `workloads.yaml`           | Maintains the steady state of bootstrapped workload servers using reusable roles. |
| `local-bootstrap-lxc.yaml` | Orchestrates the bootstrap process for LXC containers, including initial setup and application of common roles. |
| `local-bootstrap-pve.yaml` | Orchestrates the bootstrap process for PVE hosts, including initial setup and application of common roles. |

## Tasks

Ansible tasks are organized into directories based on their target or function.

- `ansible/tasks/lxc_bootstrap/`: Tasks for bootstrapping LXC containers.
- `ansible/tasks/lxc_prepare/`: Tasks related to preparing LXC environments.
- `ansible/tasks/pve_host/`: Tasks for configuring Proxmox Virtual Environment hosts.

## Configuration

All Ansible-managed tailnet hosts must have the `tag:ansible` Tailscale tag so the tailnet ACL permits management traffic.

- `ansible.cfg`: Main Ansible configuration file. Sets inventory, disables host-key checking, and auto-detects Python.
- `inventory.yaml`: Defines the hosts and groups for Ansible to manage.
- `requirements.txt`: Lists the Python dependencies for the Ansible environment.
- `.ansible-lint`: Configuration file for the Ansible Lint tool.

## Developer Setup

1.  **Navigate to the `ansible` directory**:
    ```bash
    cd ansible
    ```
2.  **Create and activate a Python virtual environment**:
    ```bash
    python3 -m venv .venv
    source .venv/bin/activate
    ```
3.  **Install dependencies**:
    ```bash
    python -m pip install --upgrade pip
    python -m pip install -r requirements.txt
    ```
4.  **Verify setup**:
    ```bash
    ansible --version
    ansible-lint --version
    ansible-config dump --only-changed
    ansible-inventory --graph
    ```
5.  **Run the linter**:
    ```bash
    ansible-lint
    ```

## Invoking Playbooks

-   **Syntax Check**:
    ```bash
    ansible-playbook <playbook.yaml> --syntax-check
    ```
    Example:
    ```bash
    ansible-playbook playbooks/local-bootstrap-pve.yaml --syntax-check
    ```

-   **Preview Changes (Check Mode)**:
    ```bash
    ansible-playbook <playbook.yaml> --check --diff
    ```
    Example:
    ```bash
    ansible-playbook playbooks/local-bootstrap-pve.yaml --check --diff
    ```

-   **Limit Execution to a Specific Host**:
    ```bash
    ansible-playbook <playbook.yaml> --check --diff --limit <hostname>
    ```
    Example:
    ```bash
    ansible-playbook playbooks/local-bootstrap-pve.yaml --check --diff --limit caba-host
    ```

-   **Apply Playbooks**:
    *   **PVE Host**:
        ```bash
        ansible-playbook playbooks/local-bootstrap-pve.yaml
        ```
    *   **LXC Container**:
        ```bash
        ansible-playbook playbooks/local-bootstrap-lxc.yaml \
          --extra-vars lxc_pve_host=<pve_host> \
          --extra-vars lxc_prepare_ctid=<container_id>
        ```
        Example:
        ```bash
        ansible-playbook playbooks/local-bootstrap-lxc.yaml \
          --extra-vars lxc_pve_host=caba-host \
          --extra-vars lxc_prepare_ctid=105
        ```

-   **Increase Verbosity**:
    ```bash
    ansible-playbook <playbook.yaml> -v
    ansible-playbook <playbook.yaml> -vvv
    ```
