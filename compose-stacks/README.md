# Compose stacks

This directory contains reusable, host-independent Docker Compose definitions.
[`OPERATIONS.md`](OPERATIONS.md) is the source of truth for stack layout,
validation, per-host c5e reconciliation, and safe handling of existing Docker
state. CI validates configuration only; each deployment host's local c5e
controller applies that host's assignments.

## Stack layout and assignments

```text
compose-stacks/<stack>/
  docker-compose.yaml
  .env.template               # optional shared values
  deployments/
    <host>/
      .env.template           # required assignment values and secrets
      docker-compose.yaml     # optional host-specific overlay
```

For example, a deployment can provide host-specific Compose configuration without changing the base stack:

```text
compose-stacks/helloworld/
  docker-compose.yaml
  .env.template
  deployments/
    traefik-lxc/
      .env.template
      docker-compose.yaml
```

The host-specific overlay is a normal Compose fragment:

```yaml
---
services:
  helloworld:
    # Host-specific Compose settings belong here.
    environment:
      DEPLOYMENT_HOST: traefik-lxc
```

Every stack here is an application stack, including `traefik/`; there is no
`docker-networking/` platform stack. Each host-local c5e controller ensures the
external `proxy` network on its own Docker daemon before reconciling assigned
applications. Applications that declare `proxy` as external must not create or
remove it.

An optional host-specific Compose overlay named
`deployments/<host>/docker-compose.yaml` is available for assigned application
stacks. c5e applies it only on its matching host; it does not determine
assignment. Assignment is controlled by `deployments/<host>/.env.template`.

The presence of that file assigns a stack to the exact short
`inventory_hostname_short`. An empty file is still an assignment. The root
`.env.template` is optional and provides shared values; host-specific values
override them. Keep `op://...` references unresolved and never commit runtime
`.env` files or resolved secrets.

`deployment_hosts` is the deployment subset of `stack_hosts` and contains
`traefik-lxc`, `docker0-lxc`, `docker-vm-dmz`, and `lxc-docker-core0`. Run
exactly one c5e controller on each host; it uses that host's local Docker socket
and reconciles only its own assignments. Initialize hosts one at a time using
each host's own c5e credential. Inspect the local `proxy` network and Docker
daemon IDs; if `proxy` already exists, use that host's exact network ID and
daemon ID together, and leave both unset if `proxy` is absent. Never share
credentials or ID pairs across hosts. Assignment changes do not authorize a
live-state handoff, and the configured `retain` policy leaves removed
assignments and orphaned resources in place.

## Remote safety

c5e does not adopt existing Docker resources merely because their Compose
project name matches. Foreign or mixed-owner resources block Up/Down, and old
automation markers do not authorize adoption or replacement. The legacy
`docker-networking` project is recognized only when both the exact local
`proxy` network ID and local Docker daemon ID match; c5e leaves the network and
its attachments untouched. Repository validation does not prove that remote
state changed, and these docs define no operational rollout or live-stack
handoff.

## Local validation

Use representative values for local validation; do not put resolved secrets in Git:

```bash
docker compose --project-name cloudflare-tunnel \
  --env-file /path/to/representative.env \
  -f compose-stacks/cloudflare-tunnel/docker-compose.yaml config --quiet
```

See each stack README for service-specific prerequisites.
