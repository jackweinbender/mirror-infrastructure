# Compose stacks

This directory contains reusable, host-independent Docker Compose definitions.
The operational source of truth for adding, validating, deploying, and
recovering stacks is [`OPERATIONS.md`](OPERATIONS.md). The application deployment workflow evaluates every application stack against every Docker host whose inventory entry has `host_roles: deploy`.

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

`docker-networking/` is the platform stack: it owns only the external `proxy` network and is reconciled first by `deploy.yaml` on every deploy host. `traefik/` is a normal assigned application stack that runs after networking is ready.

The deployment workflow supports an optional host-specific Compose overlay named `deployments/<host>/docker-compose.yaml` for assigned application stacks. During deployment, when that file exists for the target host, it is copied into the private staging directory as Compose's conventional `docker-compose.override.yaml`. This lets the remote workflow use the same Compose commands on every host while keeping host-specific composition out of the base `docker-compose.yaml`. The overlay is applied only to its matching host; it does not determine assignment. Application assignment is controlled by the presence of `deployments/<host>/.env.template`. The special `docker-networking` platform stack is deployed to every discovered deploy host and has no deployment assignments.

The presence of `deployments/<host>/.env.template` assigns a stack to that exact short inventory host identifier. An empty file is still an assignment. The root `.env.template` is optional and provides shared values; host-specific values override them. Env files may contain `op://...` references. GitHub Actions merges the files, resolves references with `op inject`, and streams the resolved `.env` directly to the private remote staging directory. Resolved secrets are never committed or written to runner artifacts.

To deploy to a new host, add `deployments/<host>/.env.template`, using a host with `host_roles: deploy` in `ansible/inventory.yaml`, then push to `main` or manually dispatch the workflow. To remove a deployment, delete that deployment directory and run the workflow. The workflow runs `docker compose down --remove-orphans` with the existing remote files and `.env` before removing the marked remote directory. It does not remove named volumes or images.

The external `proxy` network is provided by the `docker-networking` platform phase of the deployment workflow. Application Compose files that declare it as external run only after that phase succeeds; application reconciliation never removes it.

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
