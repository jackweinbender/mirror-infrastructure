# Ansible instructions

`ansible/` is the source of truth for Debian host configuration, workload
convergence, and Proxmox LXC bootstrap workflows. Read `README.md` and the
relevant role or playbook before changing behavior.

## Structure and behavior

- `roles/base/` and `roles/tailscale/` provide the baseline applied by
  `playbooks/workloads.yaml`.
- A host's `host_roles` controls optional roles such as `deploy`, `docker`, and
  `c5e_reconciler`.
- `tasks/lxc_*` and `tasks/pve_host/` are procedural bootstrap workflows, not
  steady-state roles.
- `playbooks/local-*.yaml` are operator-run bootstrap and feature workflows;
  `local` means they run from the LAN rather than the GitHub Actions tailnet.
- Application assignments may use `deploy` or `c5e_reconciler`; c5e reconciles
  assignments on its own host. No Compose deployment workflows are configured;
  retained discovery scripts still select hosts with `deploy`.
- Debian guests and Tailscale SSH are the supported workload model.

## Secrets and changes

- For long-lived service credentials on workloads, follow the VM service
  credential SOP in `README.md`: use private targeted prompts and root-only
  environment files, never inline secret literals in command arguments.
- CI uses approved Crow secrets; never commit credentials, logs, or generated
  secret files.
- Inspect inventory selection, limits, and playbook tags before running a
  command that can change a remote host.
- Prefer idempotent role changes for steady-state configuration; keep procedural
  bootstrap logic explicit and narrowly scoped.

## Validation

From the repository root, use the project virtual environment:

```bash
cd ansible
.venv/bin/ansible-lint
for playbook in playbooks/*.yaml; do
  .venv/bin/ansible-playbook "$playbook" --syntax-check
done
.venv/bin/ansible-inventory --graph
```

Run Molecule one role at a time when Docker is available. Do not run bootstrap
playbooks against real hosts without an explicit inventory and limit review.
