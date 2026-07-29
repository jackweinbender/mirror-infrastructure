# AGENTS

Guidance for humans and AI agents working in `ansible/`. See `README.md` for
setup and command reference; this file covers structure and conventions.

## Structure

| Path | Purpose |
| --- | --- |
| `roles/base/` | The Debian baseline every workload converges to: packages, the `ansible` management user, key-only sshd, unattended-upgrades, console auto-login. One task file per feature (see `roles/base/tasks/main.yml`); no feature-flag conditionals - applying the role means applying the baseline. |
| `roles/tailscale/` | Installs Tailscale and, when `tailscale_authkey` is set and the host hasn't already joined, joins the tailnet with Tailscale SSH enabled. Owns no vars but its own (`tailscale_authkey`, `tailscale_hostname`). |
| `tasks/lxc_bootstrap/` | One-shot provisioning for a fresh LXC: management user + tailnet join + inventory registration only - see "Bootstrap vs steady state" below. |
| `tasks/lxc_prepare/` | PVE-host-side prep before bootstrap can reach the container over SSH (TUN device, discovering its LAN IP). |
| `tasks/pve_host/` | Configures the Proxmox hosts themselves (`hypervisors` group), not guests. |
| `playbooks/workloads.yaml` | Steady state. Applies `base` + `tailscale` to every host in the `workloads` group. Safe to rerun; this is what CI/CD and cron should call. |
| `playbooks/local-bootstrap-lxc.yaml` | One-shot: prepares an existing LXC via its PVE host, then bootstraps it over SSH and registers it in inventory. Prompts for `lxc_pve_host` / `lxc_prepare_ctid` / `lxc_bootstrap_tailscale_authkey` if not supplied via `-e` (see README). |
| `playbooks/local-bootstrap-pve.yaml` | One-shot: configures a Proxmox host itself (`hypervisors` group). |

## Bootstrap vs steady state

Bootstrap's only job is to get a fresh container to the point where
`workloads.yaml` can take over: create the `ansible` user, join the
tailnet, register the host in `inventory.yaml`. Everything else - package
upgrades, sshd policy, unattended-upgrades, console auto-login - is
desired-state config owned by `roles/base` and applied on the first
steady-state run. Do not add features to bootstrap; add them to `roles/base`
and let `workloads.yaml` converge every host, bootstrapped or not.

## Remote access model

Tailscale SSH (`tailscale up --ssh`) is the only supported remote-access
path once a host is bootstrapped. There is no root SSH key installed and no
password set - `roles/base/tasks/ssh.yml` keeps plain sshd key-only and
reachable over the tailnet, but nothing supplies a key for it. If Tailscale
is ever unreachable, the fallback is the Proxmox web console (root, no
password - see `roles/base/tasks/autologin.yml`), not plain SSH.

All Ansible-managed hosts on the tailnet must have the `tag:ansible`
Tailscale tag so the tailnet ACL permits management traffic.

## Conventions

- **DRY:** shared configuration lives once in a role; playbooks and task
  files compose roles, they don't duplicate their logic.
- **No dead feature flags:** if a role always does something, it isn't
  gated behind a variable. To skip a feature, don't apply that role or task
  file (e.g. bootstrap borrows `roles/base` tasks_from: `users` only).
- **Idempotency:** `workloads.yaml` must be safe to run repeatedly with no
  unintended changes on a converged host.
