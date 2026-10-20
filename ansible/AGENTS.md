# Ansible instructions

`ansible/` is the source of truth for Debian host configuration, workload
convergence, and Proxmox LXC bootstrap workflows. Read `README.md` and the
relevant role or playbook before changing behavior.

## Structure and behavior

- `host_ops`, `tailscale`, and `logging` configure the Debian host-operations
  profile used by `playbooks/debian-host-ops.yaml`.
- `playbooks/stack-hosts.yaml` adds the `containers` runtime on `stack_hosts`
  and applies `secrets` plus `deploy` (c5e) on `deployment_hosts`.
- `deployment_hosts` is the child deployment capability group under
  `stack_hosts`; all four current application hosts belong to it. c5e
  reconciles assignments only on the matching host-local controller.
- Run `playbooks/c5e-reconciler.yaml` with `--limit <host>` for exactly one
  deployment host; credentials and any proxy network IDs are host-specific.
- Tasks under `tasks/lxc_*` and `tasks/pve_host/` are procedural bootstrap workflows, not
  steady-state roles.
- `playbooks/local-*.yaml` are operator-run bootstrap and feature workflows;
  `local` means they run from the LAN rather than the GitHub Actions tailnet.
- Debian guests and Tailscale SSH are the supported workload model.

## Secrets and changes

- The c5e service credential is handled by the targeted playbook and `secrets`
  role. General host/LXC secret distribution is not yet implemented.
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
