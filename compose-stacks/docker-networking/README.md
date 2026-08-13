# Docker networking platform stack

See [`../OPERATIONS.md`](../OPERATIONS.md) for the repository-wide Compose
stack and deployment process.

This stack owns the host-level Docker networking required by the other Compose stacks. It is deployed to every Docker host discovered from `ansible/inventory.yaml` with `host_roles: deploy`, before normal application reconciliation.

## What it provides

- An attachable Docker bridge network named `proxy`.

Traefik and application services are separate Compose stacks. Services that should be reachable through Traefik join the external `proxy` network and opt in with Docker labels.

## Deployment

Changes under `compose-stacks/docker-networking/` run the platform phase of `deploy.yaml`. The workflow validates the networking Compose project, stages it privately, and reconciles it on every discovered deploy host. This stack has no host assignment files because it is always deployed everywhere.

The platform owns the `proxy` network. Application stacks that declare the network as external run after this phase succeeds; application reconciliation never removes it.
