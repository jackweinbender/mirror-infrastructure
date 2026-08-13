# Script instructions

## Purpose

These Ruby scripts support GitHub Actions for Compose deployments and Terraform
component selection. Keep the root-level scripts as small, readable entrypoints:
they should explain the business logic and sequencing, not hide domain behavior
behind unrelated utility methods.

## Shared libraries

- Reusable code belongs under `lib/`.
- Extract high-level patterns such as command execution, shell quoting, output
  formatting, and error reporting before duplicating them in entrypoints.
- Put cohesive domain behavior in a named library rather than creating a
  catch-all utility file.
- Public library methods should avoid process exit and external side effects
  where practical; return values or raise descriptive errors instead.
- Preserve existing command argument handling, secret boundaries, and exit
  behavior when refactoring an entrypoint.

## Tests

- Add or update tests under `test/` for every deterministic public library
  interface.
- Use Ruby's standard-library `minitest`; do not add a dependency solely for
  these scripts.
- Test success cases, precedence/order rules, validation failures, and boundary
  conditions relevant to the public interface.
- Keep SSH, rsync, Docker, remote file writes, and 1Password injection as
  integration boundaries unless they can be tested without contacting a real
  service or exposing secrets.
- Run the library tests directly with:

  ```bash
  ruby .github/scripts/test/lib_test.rb
  ```

## Safety and secrets

- Never print or commit resolved secrets, runtime `.env` files, tokens, or
  private keys.
- Do not weaken managed deployment marker checks or automatically remove an
  unmarked remote directory.
- Preserve the platform/application deployment order and the external `proxy`
  network ownership rules documented in `compose-stacks/OPERATIONS.md`.
- Keep SSH host verification and non-interactive (`BatchMode`) behavior intact.

## Validation

For changes under this directory, run at least:

```bash
ruby .github/scripts/test/lib_test.rb
ruby .github/scripts/preflight.rb
for script in .github/scripts/*.rb .github/scripts/lib/*.rb .github/scripts/test/*.rb; do
  ruby -c "$script" || exit 1
done
git diff --check
```

If deployment behavior changes, also follow the Compose validation and workflow
instructions in `compose-stacks/OPERATIONS.md` and the repository-level
`AGENTS.md`.
