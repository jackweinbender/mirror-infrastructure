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
- Keep Compose deployment order and managed-directory marker guards intact; do not
  add broad remote cleanup. The platform network is reconciled before applications.
- Keep path filters aligned with files that affect a workflow. Check whether
  script-only changes require a manual deployment dispatch after merging.

## Deployment verification

Do not infer success from an aggregate workflow result. For script-only or
workflow-only changes that are not covered by push filters, after merging to
`main` dispatch and inspect the actual run:

```bash
gh workflow run deploy.yaml --ref main
gh run watch <run-id> --exit-status
gh run view --job <job-id> --log-failed
```

Inspect failed matrix jobs individually and report any unverified remote state.

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

Use focused tests first, then broader checks relevant to changed workflows. Do not
claim a deployment passed without checking the workflow run and relevant jobs.
