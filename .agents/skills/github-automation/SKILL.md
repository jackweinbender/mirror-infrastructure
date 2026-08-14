---
name: github-automation
description: Safely change and verify this repository's GitHub Actions workflows and Ruby automation, preserving output contracts, path triggers, deployment trust boundaries, and manual deployment verification.
---

# GitHub automation

Use this skill for changes to `.github/workflows/`, `.github/scripts/`, workflow
triggers, matrix generation, reusable Terraform automation, or deployment
verification. Read the relevant scoped `AGENTS.md`, workflow README, and called
Ruby library before editing. For Compose deployment behavior, also load the
`compose-deployments` skill and read `compose-stacks/OPERATIONS.md`.

## Design and safety rules

- Keep workflow YAML explicit and orchestration-focused. Put reusable business
  logic in `.github/scripts/lib/` and keep root scripts as readable entrypoints.
- Preserve public script contracts, especially `GITHUB_OUTPUT` names and JSON
  consumed by matrix jobs. Add/update deterministic Minitest coverage in
  `.github/scripts/test/`.
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
ruby .github/scripts/test/lib_test.rb
ruby .github/scripts/preflight.rb
for script in .github/scripts/*.rb .github/scripts/lib/*.rb .github/scripts/test/*.rb; do
  ruby -c "$script" || exit 1
done
git diff --check
```

Use focused tests first, then broader checks relevant to changed workflows. Do not
claim a deployment passed without checking the workflow run and relevant jobs.
