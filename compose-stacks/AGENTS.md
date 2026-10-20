# Compose stack instructions

`compose-stacks/` contains Docker Compose workloads and host assignments.
Compose deployment workflows have been removed; CI validates Compose but does
not deploy it. Read `OPERATIONS.md` and the relevant stack README before making
a change. Use the `compose-deployments` skill for non-trivial stack, assignment,
overlay, or deployment work.

## Repository model

- `docker-networking/` is the platform stack. It owns the external `proxy`
  network and is intended for inventory hosts with `host_roles: deploy`.
- Every other stack, including Traefik, is an assigned application stack.
- Application assignment is the presence of
  `deployments/<host>/.env.template`; an overlay alone does not assign a stack.
  Application assignment hosts need `deploy` or `c5e_reconciler`. c5e continues
  reconciling assignments on its own controller host.
- Never add `deployments/ALL/`.
- Root `.env.template` values are shared; host templates override them. Keep
  `op://...` references unresolved and never commit runtime `.env` files.
- Bind sources are type-sensitive: file sources must exist as regular files in
  the repository before Compose runs.
- Application stacks may use external `proxy`, but must not create or remove it.

## Deployment safety

Retained reconciler scripts stage privately, inject secrets remotely, validate
Compose, then publish to `/etc/compose-stacks/<stack>` using the stable project
name. Only a live directory with a regular matching
`.managed-by-github-actions` marker may be replaced or removed. Do not weaken
that guard or add broad cleanup for unmarked directories. No CI workflow invokes
these deployment scripts.

## Validation

Use representative non-secret values for local Compose checks:

```bash
ruby scripts/preflight.rb
docker compose \
  -f compose-stacks/<stack>/docker-compose.yaml \
  -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
  config --quiet
```

Omit the overlay when none exists. Also run the Ruby syntax checks and
`git diff --check` used by the repository validation pipeline. Compose
validation does not deploy; no Compose deployment workflow is available.
