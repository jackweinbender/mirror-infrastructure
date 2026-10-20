# Compose stacks

This directory contains reusable, host-independent Docker Compose definitions.
The operational source of truth for stack layout, validation, and recovery is
[`OPERATIONS.md`](OPERATIONS.md). The Compose validation pipeline checks
assignments, but there are no Compose deployment workflows. c5e continues to
reconcile assignments on its own `c5e_reconciler` host.

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

The deployment overlay is a normal Compose fragment and is copied to the staged
project as `docker-compose.override.yaml`:

```yaml
---
services:
  helloworld:
    # Host-specific Compose settings belong here.
    environment:
      DEPLOYMENT_HOST: traefik-lxc
```

`docker-networking/` is the platform stack: it owns the external `proxy`
network. The repository no longer has a CI workflow that reconciles this stack
or application stacks on deploy hosts. `traefik/` remains a normal assigned
application stack.

An optional host-specific Compose overlay named
`deployments/<host>/docker-compose.yaml` is available for assigned application
stacks. Deployment tooling copies it into private staging as
`docker-compose.override.yaml` and applies it only to its matching host; it
does not determine assignment. Application assignment is controlled by
`deployments/<host>/.env.template`. The platform stack has no assignment
directories.

The presence of `deployments/<host>/.env.template` assigns a stack to that exact
short inventory host identifier. An empty file is still an assignment. The root
`.env.template` is optional and provides shared values; host-specific values
override them. Env files may contain `op://...` references. Deployment tooling
merges the files and resolves references. Resolved secrets are never committed
or written to runner artifacts.

Application assignment files for `deploy` hosts are configuration only; pushes
and assignment changes do not automatically deploy or tear down those stacks.
Assignments on a `c5e_reconciler` host continue to be reconciled by c5e, which
independently ensures its `proxy` network. Application Compose files that
declare `proxy` as external must not remove it.

## Remote safety

Application projects live at `/etc/compose-stacks/<stack>` with stable Compose
project names equal to their stack directory names. Reconciliation scripts copy
updates to a unique private staging directory, validate with
`docker compose config --quiet`, and publish before `compose up`. Only a
directory containing a regular `.managed-by-github-actions` marker with the
matching stack name may be replaced or removed. Unmarked directories are left
for manual review.

## Local validation

Use representative values for local validation; do not put resolved secrets in Git:

```bash
docker compose --project-name cloudflare-tunnel \
  --env-file /path/to/representative.env \
  -f compose-stacks/cloudflare-tunnel/docker-compose.yaml config --quiet
```

See each stack README for service-specific prerequisites.
