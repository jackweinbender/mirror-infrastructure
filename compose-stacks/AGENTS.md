# Compose stack instructions

`compose-stacks/` contains Docker Compose workloads deployed by GitHub Actions.
Read `OPERATIONS.md` and the relevant stack README before making a change. Use
the `compose-deployments` skill for non-trivial stack, assignment, overlay, or
deployment work.

## Repository model

- `docker-networking/` is the platform stack. It owns the external `proxy`
  network and is deployed to every inventory host with `host_roles: deploy`.
- Every other stack, including Traefik, is an assigned application stack.
- Application assignment is the presence of
  `deployments/<host>/.env.template`; an overlay alone does not assign a stack.
- Never add `deployments/ALL/`.
- Root `.env.template` values are shared; host templates override them. Keep
  `op://...` references unresolved and never commit runtime `.env` files.
- Bind sources are type-sensitive: file sources must exist as regular files in
  the repository before Compose runs.
- Application stacks may use external `proxy`, but must not create or remove it.

## Deployment safety

The workflow stages privately, injects secrets remotely, validates Compose,
then publishes to `/etc/compose-stacks/<stack>` using the stable project name.
Only a live directory with a regular matching
`.managed-by-github-actions` marker may be replaced or removed. Do not weaken
that guard or add broad cleanup for unmarked directories.

## Validation

Use representative non-secret values for local Compose checks:

```bash
ruby .github/scripts/preflight.rb
docker compose \
  -f compose-stacks/<stack>/docker-compose.yaml \
  -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
  config --quiet
```

Omit the overlay when none exists. Also run the Ruby syntax checks and
`git diff --check` listed in `.forgejo/workflows/AGENTS.md`. Script-only workflow
changes may require a manual `deploy.yaml` dispatch after merging; do not claim
a deployment passed without checking the actual workflow result.
