# Terraform instructions

`terraform/` contains independent cloud and virtualization components. Read
`README.md` and the component README before changing a component.

## Component boundaries

- Keep each component isolated in its existing directory and state backend.
- Do not move resources between components or change backend identity casually.
- Follow the existing provider, variable, output, and backend conventions in the
  component.
- Keep component names synchronized with `terraform/components.json` and
  the Crow component matrix.

## State and credentials

- Prefer plan-only validation; apply only when explicitly requested or through
  the intended GitHub Actions workflow.
- Never commit Terraform state, plans containing secrets, provider credentials,
  private keys, or resolved 1Password values.
- Preserve the existing OIDC, Workload Identity Federation, and 1Password
  authentication paths.

## Validation

From the changed component directory, use the existing Terraform toolchain:

```bash
terraform fmt -check
terraform init -backend=false
terraform validate
terraform plan
```

Use the component's README for provider-specific prerequisites and backend-aware
commands. From the repository root, also run the Terraform component manifest
validation and `git diff --check`. Do not run `terraform apply` unless the task
explicitly authorizes it.
