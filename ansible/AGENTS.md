# AGENTS

Guidance for humans and AI agents working in `ansible/`. See `README.md` for
setup and command reference; this file covers structure and conventions.

## Structure

| Path | Purpose |
| --- | --- |
| `roles/base/` | The Debian baseline every workload converges to: packages, the `ansible`/personal-account users, key-only sshd (full-file ownership, merged-config validation), SSH host-key regeneration (guards against cloned-template duplicates), unattended-upgrades, needrestart, locale/timezone/NTP, console auto-login, login banner (MOTD), local log retention (journald + logrotate caps). One task file per feature (see `roles/base/tasks/main.yml`); no feature-flag conditionals - applying the role means applying the baseline. Debian only - no Ubuntu/other-distro support. |
| `roles/tailscale/` | Installs Tailscale and, when `tailscale_authkey` is set and the host hasn't already joined, joins the tailnet with Tailscale SSH enabled. Owns no vars but its own (`tailscale_authkey`, `tailscale_hostname`). |
| `roles/docker/` | Docker Engine (official apt repo, not `docker.io`) + compose plugin + docker-group membership, for hosts that run compose-stacks. Debian-only - asserts `ansible_distribution == 'Debian'` and fails fast with a clear message otherwise (Docker's `linux/debian` and `linux/ubuntu` apt repos are not interchangeable). Preflights the two Proxmox LXC feature flags Docker needs (`nesting`, `keyctl`) via the actual capability they gate (cgroup delegation, the `keyctl()` syscall) since neither has a direct in-guest readout; fails fast with the `pct set` command to fix it rather than a confusing dockerd crash. Applied per-host via `host_roles` in inventory, not a hardcoded play (see below). |
| `tasks/lxc_bootstrap/` | One-shot provisioning for a fresh LXC: management user + tailnet join + inventory registration only - see "Bootstrap vs steady state" below. |
| `tasks/lxc_prepare/` | PVE-host-side prep before bootstrap can reach the container over SSH (TUN device, discovering its LAN IP). |
| `tasks/pve_host/` | Configures the Proxmox hosts themselves (`hypervisors` group), not guests. |
| `playbooks/workloads.yaml` | Steady state. Applies `base` + `tailscale` to every host in the `workloads` group, then applies each host's specialized roles from its `host_roles` list in inventory (e.g. `host_roles: [docker]`). Safe to rerun; this is what CI/CD and cron should call. |
| `playbooks/local-bootstrap-lxc.yaml` | One-shot: prepares an existing LXC via its PVE host, then bootstraps it over SSH and registers it in inventory. Prompts for `lxc_pve_host` / `lxc_prepare_ctid` / `lxc_bootstrap_tailscale_authkey` if not supplied via `-e` (see README). |
| `playbooks/local-bootstrap-pve.yaml` | One-shot: configures a Proxmox host itself (`hypervisors` group). |

## Specialized roles (`host_roles`)

Beyond the `base` + `tailscale` baseline every workload gets, per-host extras
are declared in `inventory.yaml` as a `host_roles` list on that host, not as
a hardcoded play in `workloads.yaml`:

```yaml
workloads:
  hosts:
    traefik-lxc.tortoise-noodlefish.ts.net:
      host_roles: [docker]
```

`workloads.yaml` has one generic task that loops over `host_roles` and
`include_role`s each entry (`loop_control.loop_var: specialized_role` -
deliberately not `item`, to avoid shadowing any loop variable used inside
the included role itself). Adding a new specialized role for a host means
editing inventory only; the playbook never changes. Roles applied this way
are still full Ansible roles under `roles/` with their own `defaults/main.yml`
and `tasks/main.yml` - `host_roles` just controls which hosts get them.

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

## Debian-only, deliberately

Every role in this repo assumes Debian. `roles/docker` asserts it and fails
fast; `roles/base` doesn't assert but uses Debian-specific package names and
paths that will misbehave on other distros (e.g. Ubuntu's `noble` doesn't
exist under Docker's `linux/debian` apt tree; `update-notifier-common` is
Ubuntu-only and doesn't exist on Debian at all - both were real failures
hit against live hosts). If a host in `workloads` turns out to be
Ubuntu-based (verify: `ansible <host> -m setup -a "filter=ansible_distribution*"`),
treat it as an exception to fix at the infra level (rebuild as Debian), not
a reason to add distro-detection branching to these roles.

## Testing

All three production roles have Molecule tests for independent validation without touching live infrastructure:

| Role | Test | Assertions | Command |
|------|------|-----------|----------|
| `roles/base/` | `roles/base/molecule/` | 6 (user, packages, locale, tz, ssh, shells) | `molecule test -s base` |
| `roles/docker/` | `roles/docker/molecule/` | 8 (engine, compose, groups, permissions) | `molecule test -s docker` |
| `roles/tailscale/` | `roles/tailscale/molecule/` | 10 (binary, daemon, repo, gpg) | `molecule test -s tailscale` |

**Before making changes:**
1. Run the relevant role test: `molecule test -s {role}`
2. Verify idempotency: `molecule idempotent -s {role}` (apply twice, second run should change nothing)
3. Inspect interactively: `molecule converge -s {role}` + `docker exec -it debian-bookworm bash`

**Documentation:**
- `TESTING.md` — Complete testing guide
- `TESTING-TASKS.md` — Bootstrap task testing (syntax check + dry-run, not unit tests)
- `TESTING-INDEX.md` — Navigation guide
- `roles/{role}/molecule/README.md` — Role-specific test docs

## Conventions

- **DRY:** shared configuration lives once in a role; playbooks and task
  files compose roles, they don't duplicate their logic.
- **No dead feature flags:** if a role always does something, it isn't
  gated behind a variable. To skip a feature, don't apply that role or task
  file (e.g. bootstrap borrows `roles/base` tasks_from: `users` only).
- **Idempotency:** `workloads.yaml` must be safe to run repeatedly with no
  unintended changes on a converged host.
