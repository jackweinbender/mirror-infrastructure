# Repository instructions

This repository manages personal infrastructure as code. Make the smallest
focused change that satisfies the request, preserve existing conventions, and
treat unrelated working-tree changes as protected.

## Before editing

- Read the relevant scoped `AGENTS.md`, README, and nearby implementation.
- Check the worktree first:

  ```bash
  git --no-optional-locks status --short --branch
  ```

- Inspect workflows, inventories, call sites, and deployment boundaries before
  changing behavior.
- Never commit secrets, generated runtime `.env` files, private keys, Terraform
  state, or other generated credentials.

## Scoped guidance

- [`ansible/AGENTS.md`](ansible/AGENTS.md): host configuration, inventory,
  playbooks, roles, and Ansible validation.
- [`compose-stacks/AGENTS.md`](compose-stacks/AGENTS.md): stack layout,
  assignments, overlays, deployment safety, and Compose validation.
- [`terraform/AGENTS.md`](terraform/AGENTS.md): component boundaries, state,
  credentials, and Terraform validation.

- [`scripts/AGENTS.md`](scripts/AGENTS.md): Ruby libraries, entrypoints, and
  unit tests.

For Compose work, also load the project-local `compose-deployments` skill and
read [`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md), the
operational source of truth for stack layout and deployment recovery.

## Cross-cutting rules

- Prefer existing dependencies, scripts, and patterns. Keep root entrypoints
  and workflow YAML focused on orchestration; put reusable logic in the scoped
  libraries and source directories.
- Keep behavior changes minimal. Add comments only for non-obvious constraints.
- Preserve secret handling, SSH host verification, Tailscale access, and guarded
  remote cleanup. Do not manually delete remote deployment directories without
  explicit recovery authorization and marker/ownership inspection.
- Update tests, documentation, validation, and call sites when behavior changes.
- Do not commit, create branches, force-push, or perform destructive Git actions
  unless explicitly requested.

## Completion

Before finishing, review the complete diff including untracked files, run
focused and broader applicable validation, run `git diff --check`, inspect final
status, and report exactly which commands passed. Call out failed workflows,
unverified remote state, warnings, and follow-up work rather than implying
success.
