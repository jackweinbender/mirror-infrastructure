# Workflow instructions

## Purpose

These workflows validate the repository and publish infrastructure changes. Keep
workflow steps explicit about their inputs, trust boundaries, and failure
behavior. Prefer existing scripts and repository conventions over embedding
complex shell or deployment logic directly in YAML.

## Compose deployment workflow

- `deploy.yaml` performs the Compose deployment lifecycle: preflight,
  `docker-networking` platform reconciliation, then assigned application stack
  reconciliation.
- `docker-networking` owns the external `proxy` network and is applied to every
  host discovered with `host_roles: deploy`.
- All other Compose stacks, including Traefik, are assigned application stacks.
- Preserve stable Compose project names equal to the stack name.
- Preserve private staging, managed deployment markers, remote secret injection,
  and the refusal to replace or remove unmarked live directories.
- Do not expose resolved secrets in logs, arguments, artifacts, or workflow
  outputs.
- Preserve SSH host verification, Tailscale connectivity, and non-interactive
  SSH behavior.
- Do not add broad cleanup behavior for deleted or unmarked remote directories.

The detailed stack layout and recovery process are documented in
`compose-stacks/OPERATIONS.md`.

## Script changes

When a workflow invokes a Ruby script under `.github/scripts/`:

- Keep business logic in the script rather than duplicating it in YAML.
- Update or add library tests under `.github/scripts/test/` for deterministic
  public interfaces.
- Preserve the script's output contract, especially `GITHUB_OUTPUT` names and
  JSON formats consumed by matrix jobs.
- Run the script's focused tests and repository preflight before changing the
  workflow behavior.

## Validation

For workflow or script changes, run:

```bash
ruby -ryaml -e "Dir['.forgejo/workflows/*.{yml,yaml}'].each { |path| YAML.load_file(path) }"
ruby .github/scripts/test/lib_test.rb
ruby .github/scripts/preflight.rb
for script in .github/scripts/*.rb .github/scripts/lib/*.rb .github/scripts/test/*.rb; do
  ruby -c "$script" || exit 1
done
git diff --check
```

For Compose deployment changes, also follow the representative `docker compose
config --quiet` validation in `compose-stacks/OPERATIONS.md`.

## Change triggers and deployment verification

- Keep path filters aligned with the files that affect a workflow.
- Script-only workflow changes may not be covered by the Compose push filter.
  After merging such changes to `main`, manually dispatch the deployment when
  appropriate:

  ```bash
  gh workflow run deploy.yaml --ref main
  gh run watch <run-id> --exit-status
  gh run view --job <job-id> --log-failed
  ```

- Do not claim a deployment succeeded without checking the actual workflow run
  and relevant matrix jobs.
- Never commit secrets, runtime `.env` files, private keys, or Terraform state.
