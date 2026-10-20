# Compose stack operations

This runbook describes the repository's Compose layout, per-host c5e
reconciliation, validation, and safe handling of existing Docker state. CI
validates configuration; each deployment host's local c5e controller applies
only the assignments for that host.

## Architecture

Every directory under `compose-stacks/` is an application stack, including
Traefik. There is no `docker-networking` Compose stack: c5e ensures the external
`proxy` network on its own Docker host before reconciling assigned applications.
Application stacks may use `proxy` as an external network but must not create,
delete, or otherwise manage it.

`deployment_hosts` is the deployment subset of `stack_hosts` and contains the
short `inventory_hostname_short` values `traefik-lxc`, `docker0-lxc`,
`docker-vm-dmz`, and `lxc-docker-core0`. Exactly one c5e controller belongs on
each deployment host. A controller uses that machine's local Docker daemon and
reconciles only assignments for its own exact short host ID; it is not a remote
deployment controller.

CI preflight checks repository configuration, including inventory membership,
stack names, environment templates, assignments, overlays, and Compose
configuration. It does not connect to hosts or change remote state.

## Standard stack shape

```text
compose-stacks/<stack>/
  docker-compose.yaml
  .env.template                 # optional shared values
  deployments/
    <host>/
      .env.template             # assignment; may contain op:// references
      docker-compose.yaml       # optional host-specific Compose overlay
```

Additional files such as application configuration, certificates, or dynamic
route definitions stay in the stack directory and are copied with the base
Compose project.

### Assignment

The presence of `deployments/<host>/.env.template` assigns the stack to that
exact short inventory host ID. An empty template is still an assignment. The
host must belong to `deployment_hosts`; preflight validates assignments against
that group. Keep existing assignment directories in place unless the stack's
intended placement is explicitly changing.

There is no `deployments/ALL/` convention. Each application stack lists its
actual host assignments. c5e on each host ensures its local `proxy` network
before reconciling that host's assigned applications.

### Compose overlays

An optional `deployments/<host>/docker-compose.yaml` is a host-specific Compose
overlay, not an assignment. c5e applies it only on the matching host. Use an
overlay for host-specific mounts, ports, resources, or service settings; keep
common services and defaults in the root `docker-compose.yaml`.

### Environment templates

Use `.env.template` consistently:

- Root `.env.template` contains values shared by all assignments and is
  optional.
- `deployments/<host>/.env.template` contains host-specific values and is
  required for an application assignment.
- Host-specific values override root values.
- Secret references use `op://...`; resolved secrets must never be committed.

Keep `op://...` references in templates and never commit resolved secrets or
runtime `.env` files. CI must never receive resolved secret values.
Reconciliation runs only through the c5e controller local to its assigned host.

## Filesystem and bind-mount rules

Docker creates a missing bind-mount source as a directory. A path intended to
be a file must therefore exist in the repository as a regular file before
Compose runs. For example:

```yaml
volumes:
  - ./traefik.yml:/etc/traefik/traefik.yml:ro
```

requires `traefik.yml` to be a file beside `docker-compose.yaml`, not a nested
or missing path. Incorrect paths can produce root-owned directories because
Docker creates bind sources through the Docker daemon. This can both prevent
the service from starting and make later filesystem cleanup harder.

Before opening a change, check every file bind source:

```bash
find compose-stacks/<stack> -type f -print
# Then verify each left-hand bind source in the Compose files is a regular file.
```

Prefer read-only mounts for configuration. A service that must write persistent
state should write to a deliberately designed named volume or data directory,
not into the checked-out Compose project. On LXC Docker hosts explicitly
configured with `containers_configure_data_root: true`, named volumes are stored
below `/srv/guest-volumes/docker`; the LXC mount itself is provisioned by the
local Proxmox bootstrap workflow, not by Compose. Compose does not create
per-stack host directories for named volumes.

`docker-vm-dmz` is a deliberate exception: it is a VM and keeps Docker's data
under the VM-local `/var/lib/docker`. Its persistence therefore depends on
whole-VM backups or a separate offsite backup job. Do not assume the LXC
`/primary/guest-volumes/<hostname>` bind-mount convention applies to VMs.

## Per-host c5e reconciliation and remote-state safety

Each deployment host has its own c5e controller, exact short host ID, and local
Docker socket. Initialize one host at a time using that host's own c5e credential.
If `proxy` already exists, supply both that host's exact network ID and local
Docker daemon ID; leave both unset when no local `proxy` exists. Never reuse a
credential or either ID across hosts. Do not treat a multi-host change as an
operational rollout or live-stack handoff. c5e ensures the local `proxy` network
before that host's assigned applications.

The Ansible role persists a supplied migration approval in a root-only file so
routine convergence cannot remove it before c5e accepts the network. After
confirming acceptance, clear it with a targeted stack-host convergence:

```bash
cd ansible
.venv/bin/ansible-playbook playbooks/stack-hosts.yaml \
  --limit <host> -e deploy_proxy_network_migration_clear=true
```

c5e does not adopt existing Docker resources merely because their Compose
project name matches a stack. Existing resources with foreign or mixed owners
block c5e Up/Down operations. Old automation marker files do not authorize
adoption or replacement. The configured `retain` removal policy leaves projects
and orphaned resources in place when assignments are removed; an assignment
change is not proof that remote state was removed or handed off.

The legacy `docker-networking` project name is recognized only for the narrowly
identified local `proxy` network when both its exact network ID and local Docker
daemon ID are supplied. That migration check leaves the network and its
attachments untouched. Never reuse network or daemon IDs from another host.

## Adding or changing a stack

1. Create the stack directory and base `docker-compose.yaml`.
2. Add the root `.env.template` if shared values are needed.
3. Add one `deployments/<host>/.env.template` for each intended host in
   `deployment_hosts`; preserve unrelated existing assignments.
4. Add a host overlay only when the base Compose definition cannot express the
   host-independent configuration.
5. Declare `proxy` as external when needed. c5e provides it locally on each
   deployment host; provision other external networks separately.
6. Check bind-mount source types, especially file mounts.
7. Run local validation (below). CI validation does not deploy or prove that
   remote state changed; each host-local c5e controller reconciles only its own
   assignments.

Changing assignments does not transfer ownership of a live project or establish
a safe cross-host migration. Plan any live-state handoff separately and do not
remove or replace resources merely because an assignment moved.

## Validation

Preflight is the authoritative repository-wide check:

```bash
ruby scripts/preflight.rb
```

Useful focused checks are:

```bash
git diff --check

docker compose \
  -f compose-stacks/<stack>/docker-compose.yaml \
  -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
  config --quiet
```

The second `-f` is optional. Use representative non-secret values locally.

## Failure and recovery process

When c5e reports an ownership conflict or a reconciliation failure, inspect the
affected host, exact local Docker daemon, project, and resource ownership before
changing anything. Never infer ownership from a Compose project name or an old
automation marker. Do not manually delete, adopt, or replace conflicting live
resources as a routine recovery step.

For the old `docker-networking` project, only the exact local `proxy` network
and Docker daemon IDs qualify for the narrow migration recognition described
above; c5e leaves the network and attached containers untouched. If IDs do not
match exactly, stop and investigate rather than weakening the ownership guard.

Preflight and Compose validation check repository configuration only. They do
not prove that a controller has been initialized, that a host reconciled its
assignments, or that any remote state changed. This documentation does not
define an operational rollout or live-stack handoff.

## Security rules

- Never print, commit, or upload resolved secrets; keep runtime `.env` files out
  of Git.
- Keep each host's c5e credentials and Docker socket access local to that host.
- Do not reuse another host's Docker daemon or network ID.
- Do not treat a matching project name or legacy marker file as proof that c5e
  owns existing Docker resources.
- Do not weaken c5e's refusal to operate on foreign or mixed-owner resources.
- Keep shared `proxy` network ownership with c5e; application stacks must not
  create or remove it.
