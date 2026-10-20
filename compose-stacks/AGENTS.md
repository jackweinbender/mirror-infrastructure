# Compose stack instructions

`compose-stacks/` contains Docker Compose workloads and host assignments.
Read `OPERATIONS.md` and the relevant stack README before making a change. Use
the `compose-deployments` skill for non-trivial stack, assignment, overlay, or
deployment work. CI validates Compose configuration; host-local c5e controllers
reconcile deployment assignments.

## Repository model

- Every directory is an application stack, including Traefik; there is no
  `docker-networking` stack.
- `deployments/<host>/.env.template` assigns a stack to the exact short
  `inventory_hostname_short`; an overlay alone does not assign a stack.
  `deployment_hosts` is the deployment subset of `stack_hosts`: `traefik-lxc`,
  `docker0-lxc`, `docker-vm-dmz`, and `lxc-docker-core0`.
- Run exactly one c5e controller per deployment host. It uses that host's local
  Docker socket and reconciles only that host's assignments. Initialize hosts
  one at a time using each host's own c5e credential. If `proxy` already exists,
  use both that host's exact network ID and Docker daemon ID; otherwise leave
  both unset. Never reuse a credential or either ID across hosts. c5e ensures
  the local external `proxy` network before assigned applications; application
  stacks must not create or remove it.
- Never add `deployments/ALL/`.
- Root `.env.template` values are shared; host templates override them. Keep
  `op://...` references unresolved and never commit runtime `.env` files.
- Bind sources are type-sensitive: file sources must exist as regular files in
  the repository before Compose runs.

## Deployment safety

c5e does not adopt existing Docker resources just because a Compose project name
matches. Foreign or mixed-owner resources block Up/Down; old automation marker
files are not adoption permission. Its `retain` removal policy leaves projects
and orphaned resources when assignments are removed. For the legacy
`docker-networking` project, migration recognition requires the exact local
`proxy` network ID and Docker daemon ID together; c5e leaves the network and
attachments untouched. Do not treat an assignment change as a live-state
handoff.

## Validation

Use representative non-secret values for local Compose checks:

```bash
ruby scripts/preflight.rb
docker compose \
  -f compose-stacks/<stack>/docker-compose.yaml \
  -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
  config --quiet
```

Omit the overlay when none exists. CI validation checks configuration only; it
does not prove that a host reconciled or that remote state changed. Keep any
live-state handoff outside routine assignment edits.
