# Docker networking platform stack

See [`../OPERATIONS.md`](../OPERATIONS.md) for the repository-wide Compose
stack and deployment process.

This stack defines host-level Docker networking for other Compose stacks. The
repository no longer has a CI deployment workflow for it; Compose validation
checks its configuration but does not reconcile it on deploy hosts.

## What it provides

- An attachable Docker bridge network named `proxy`.

Traefik and application services are separate Compose stacks. Services that should be reachable through Traefik join the external `proxy` network and opt in with Docker labels.

## Deployment

The `proxy` network is provided by this stack and must exist before dependent
application stacks run. The repository's CI validates this Compose project but
does not deploy it. c5e independently ensures `proxy` on its own controller
host.
