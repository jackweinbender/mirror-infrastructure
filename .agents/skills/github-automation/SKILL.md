---
name: github-automation
description: Safely maintain this repository's retained Ruby automation and CI contracts after workflow removal, preserving output contracts and deployment trust boundaries.
---

# GitHub automation

Use this skill for changes to `scripts/`, CI contracts, matrix selection, or
deployment verification. Read the relevant scoped `AGENTS.md` and
called Ruby library before editing. For Compose deployment behavior, also load
the `compose-deployments` skill and read `compose-stacks/OPERATIONS.md`.

## Design and safety rules

- Keep workflow YAML explicit and orchestration-focused. Put reusable business
  logic in `scripts/lib/` and keep root scripts as readable entrypoints.
- Preserve public script contracts, especially `GITHUB_OUTPUT` names and JSON
  consumed by matrix jobs. Add/update deterministic Minitest coverage in
  `scripts/test/`.
- Preserve secret boundaries: never print, commit, upload, or pass resolved
  secrets as command-line arguments. Keep SSH host verification, Tailscale
  connectivity, and non-interactive SSH behavior intact.
- Keep Compose reconciliation order and managed-directory marker guards intact
  in retained scripts; no Compose deployment workflows are configured.
- Keep path filters aligned with the workflows that remain. Compose validation
  does not deploy stacks, and no deployment dispatch is available.

## Deployment verification

Compose deployment workflows have been removed. Do not attempt a deployment
workflow dispatch or infer remote deployment success from a validation run.
For retained script changes, validate the scripts and report that remote state
was not changed unless an authorized deployment process was run separately.

## Validation

From the repository root run:

```bash
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7
ruby scripts/test/lib_test.rb
ruby scripts/preflight.rb
for script in scripts/*.rb scripts/lib/*.rb scripts/test/*.rb; do
  ruby -c "$script" || exit 1
done
git diff --check
```

Use focused tests first, then broader checks relevant to the changed workflows.
Claim deployment success only with evidence from the relevant workflow or an
authorized deployment process.
