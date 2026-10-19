# Compose stacks

This directory contains reusable, host-independent Docker Compose definitions.
The operational source of truth for adding, validating, deploying, and recovering
stacks is [`OPERATIONS.md`](OPERATIONS.md). GitHub Actions reconciles application
assignments only on `deploy` hosts; `c5e_reconciler` assignments pass preflight
but are handled by c5e and excluded from GitHub Actions targets.

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

`docker-networking/` is the platform stack: it owns only the external `proxy`
network and is reconciled first by `.crow/deploy.yaml` on deploy hosts only.
The `.crow/deploy-<stack>.yaml` workflows reconcile assigned applications on
deploy hosts after the platform workflow; c5e handles application assignments
on `c5e_reconciler` hosts, which are excluded from GitHub Actions discovery and
matrices. `traefik/` remains a normal assigned application stack.

The deployment workflow supports an optional host-specific Compose overlay named
`deployments/<host>/docker-compose.yaml` for assigned application stacks. It is
copied into private staging as `docker-compose.override.yaml` and applied only
to its matching host; it does not determine assignment. Application assignment
is controlled by `deployments/<host>/.env.template`. The platform stack is
deployed to every discovered deploy host and has no assignment directories.

The presence of `deployments/<host>/.env.template` assigns a stack to that exact
short inventory host identifier. An empty file is still an assignment. The root
`.env.template` is optional and provides shared values; host-specific values
override them. Env files may contain `op://...` references. GitHub Actions
merges the files, resolves references with `op inject`, and streams resolved
`.env` files to private remote staging. Resolved secrets are never committed or
written to runner artifacts.

For a GitHub Actions-managed application, add an assignment for a host with
`host_roles: deploy`. A `c5e_reconciler` host may also have application
assignments; preflight validates them, but GitHub Actions does not target that
host and c5e reconciles them. Removing a deploy-host assignment and running its
stack workflow invokes `docker compose down --remove-orphans` before removing
the marked directory; named volumes and images are retained. c5e-managed
assignments follow the controller's `--removal-policy=retain` behavior instead.

The `docker-networking` platform workflow provides `proxy` on deploy hosts.
On a `c5e_reconciler` host, c5e independently ensures its `proxy` network.
Application Compose files that declare `proxy` as external must not remove it.

## Remote safety

Application projects live at `/etc/compose-stacks/<stack>` with stable Compose project names equal to the stack directory name. Updates are copied to a unique private staging directory, validated with `docker compose config --quiet`, and atomically published before `compose up`. Only a directory containing a regular `.managed-by-github-actions` marker whose recorded stack name matches its directory may be replaced or removed. Unmarked directories are left for manual review.

## Local validation

Use representative values for local validation; do not put resolved secrets in Git:

```bash
docker compose --project-name cloudflare-tunnel \
  --env-file /path/to/representative.env \
  -f compose-stacks/cloudflare-tunnel/docker-compose.yaml config --quiet
```

See each stack README for service-specific prerequisites.
