# Ansible

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
ansible-playbook core.yaml --syntax-check
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
