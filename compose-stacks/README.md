# Compose stacks

This directory contains reusable, host-independent Docker Compose definitions. The application deployment workflow evaluates every application stack against every Docker host whose inventory entry has `host_roles: deploy`.

## Stack layout and assignments

```text
compose-stacks/<stack>/
  docker-compose.yaml
  deployments/
    _shared.env
    <host>.env
```

`docker-host/` is the platform exception: it owns Traefik and the external `proxy` network and is deployed only by `deploy-docker-platform.yaml`. It is never reconciled or removed by the application workflow.

The platform workflow supports an optional host-specific Compose overlay named `docker-compose.<host>.yaml`. During platform deployment, when that file exists for the target host, it is copied into the private staging directory as Compose's conventional `docker-compose.override.yaml`. This lets the remote workflow use the same Compose commands on every host while keeping host-specific composition out of the base `docker-compose.yaml`. The overlay is applied only to its matching host; it does not determine assignment. The same convention can be extended to application stacks if they later need host-specific Compose structure; assignment would still be controlled solely by `deployments/<host>.env`.

The presence of `deployments/<host>.env` assigns a stack to that exact short inventory host identifier. An empty file is still an assignment. `_shared.env` is optional and is not an assignment. Shared values are merged first; host-specific values override them. Templates may contain `op://...` references. GitHub Actions merges the templates, resolves references with `op inject`, and streams the resolved `.env` directly to the private remote staging directory. Resolved secrets are never committed or written to runner artifacts.

To deploy to a new host, add `<host>.env` under `deployments/`, using a host with `host_roles: deploy` in `ansible/inventory.yaml`, then push to `main` or manually dispatch the workflow. To remove a deployment, delete that assignment file and run the workflow. The workflow runs `docker compose down --remove-orphans` with the existing remote files and `.env` before removing the marked remote directory. It does not remove named volumes or images.

The external `proxy` network must already be provided by the platform workflow. Application Compose files that declare it as external fail clearly when the platform is absent; the application workflow never creates or removes it.

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
