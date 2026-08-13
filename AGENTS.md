# Agent instructions

## Repository purpose

This repository manages personal infrastructure as code:

- `terraform/` provisions cloud and virtualization resources.
- `ansible/` configures hosts and baseline services.
- `compose-stacks/` contains Docker Compose workloads deployed to Docker hosts
  by GitHub Actions over Tailscale.
- `.github/workflows/` contains CI/CD workflows.

Make the smallest focused change that satisfies the request. Preserve existing
conventions and avoid unrelated cleanup.

## Before changing code

1. Read the relevant README and nearby implementation.
2. Check the working tree before editing:

   ```bash
   git --no-optional-locks status --short --branch
   ```

3. Treat existing user changes as protected. Do not overwrite, revert, or
   delete unrelated modifications.
4. Inspect the relevant workflow, script, inventory, and call sites before
   changing deployment behavior.
5. Never commit secrets, generated runtime `.env` files, private keys, or
   Terraform state.

## Compose deployments

For any work involving `compose-stacks/`, load the project-local
`compose-deployments` skill and read [`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md).
Those documents are the source of truth for stack layout and deployment
operations.

The essential rules are:

- `compose-stacks/docker-networking/` is the platform stack. It owns the
  external `proxy` network and is applied to every inventory host with
  `host_roles: deploy`.
- Every other stack, including Traefik, is an assigned application stack.
- Do not add `deployments/ALL/`; application assignments are explicit.
- A stack assignment is the presence of
  `deployments/<host>/.env.template`.
- A host overlay at `deployments/<host>/docker-compose.yaml` is optional and
  does not assign the stack. It is staged as
  `docker-compose.override.yaml`.
- Use `.env.template` consistently. Root templates provide shared values;
  host templates override them. Keep `op://...` references unresolved in Git.
- Do not create or commit runtime `.env` files.
- Treat bind sources as type-sensitive. File sources must exist as regular
  files before Compose runs; a missing source can become a root-owned directory
  created by Docker and break both the service and cleanup.
- Do not weaken the managed marker guard or automatically remove an unmarked
  live directory. Migration recovery must use a narrow, explicit predicate.
- Do not make application stacks create or remove the shared `proxy` network.

The deployment lifecycle is platform first, applications second. The workflow
stages and validates privately, injects secrets remotely, publishes to
`/etc/compose-stacks/<stack>`, and uses the stable Compose project name equal
to the stack name.

## Compose validation

For Compose or deployment changes, run the repository checks that apply:

```bash
ruby .github/scripts/preflight.rb
ruby -c .github/scripts/preflight.rb
ruby -c .github/scripts/reconcile-platform.rb
ruby -c .github/scripts/reconcile-host.rb
ruby -c .github/scripts/discover-deploy-hosts.rb
git diff --check
```

Validate changed Compose files with representative non-secret values:

```bash
docker compose \
  -f compose-stacks/<stack>/docker-compose.yaml \
  -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
  config --quiet
```

Omit the overlay file when no overlay exists. Warnings for unset secret
variables can be expected locally because CI supplies them through 1Password.

A push to `main` automatically runs Compose deployment only for changes under
`compose-stacks/**`, `ansible/inventory.yaml`, or the deployment workflow. For
script-only workflow changes, manually dispatch and monitor the workflow:

```bash
gh workflow run deploy.yaml --ref main
gh run watch <run-id> --exit-status
gh run view --job <job-id> --log-failed
```

Do not claim a deployment passed without checking the actual workflow result.

## Terraform

Keep Terraform components isolated in their existing directories. Follow the
component README and existing backend/provider conventions. Do not change
backend state, provider identity, or apply behavior casually.

For Terraform changes, at minimum use the component's existing formatting and
validation commands. Prefer plan-only validation unless the user explicitly
requests an apply. Never expose Terraform variables or state containing
secrets.

## Ansible

Use the existing roles, inventories, and playbook conventions. Validate syntax
and lint changes with the repository's Ansible tooling where available. Do not
make a playbook target production hosts unintentionally; inspect inventory
selection and limits before running it.

## Secrets and remote access

- Secrets are loaded through 1Password and injected by CI.
- Do not print secret values, include them in command arguments, or write them
  to artifacts.
- Preserve Tailscale connectivity and SSH host verification in workflows.
- Avoid ad hoc SSH changes to production hosts. If remote inspection is
  necessary, use the repository's guarded workflow or clearly explain the
  limitation.
- Do not manually delete remote deployment directories unless the user
  explicitly authorizes recovery and the directory's ownership/marker state
  has been inspected.

## Editing and implementation style

- Prefer existing dependencies, scripts, and patterns.
- Keep behavior changes minimal and explain non-obvious safety constraints in
  code or documentation.
- Do not add comments that merely restate code.
- Update tests, validation, documentation, and call sites when behavior
  changes.
- Do not commit or create branches unless explicitly requested.
- Do not use force-push or destructive Git commands.

## Completion checklist

Before finishing:

1. Review the complete diff, including untracked files.
2. Run focused validation, then broader repository validation when practical.
3. Check `git diff --check` and the final worktree status.
4. Report exactly what was changed and which commands actually passed.
5. Call out warnings, failed workflows, unverified remote state, or follow-up
   work instead of implying success.
6. Commit and push only when the user has requested it or the task context
   clearly authorizes it.
