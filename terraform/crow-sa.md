# Terraform cloud authentication for Crow (service-account keys)

Crow Terraform `plan`/`apply` authenticates to AWS and GCP with **static
service-account credentials stored as Crow secrets**. We deliberately skipped
OIDC/IdP — Crow can't mint ID tokens natively, and static keys are the simplest
path. This page lists the exact keys to create and the Crow secrets to set.

## What you must create

### AWS — dedicated Terraform service account

1. Create a long-lived AWS credential (access key) in your `325498355308`
   account for the Terraform identity. Prefer a **dedicated IAM user/service
   account** scoped to only the Terraform resources (Route53 `labs.*`, S3
   bucket, CloudFront, ACM). Do not use a human's key.
2. Grant it the same permissions the prior `GithubActionsRole` had (Route53,
   S3, CloudFront, ACM, and S3 read/write for the `tf-backend-61rckk` state
   bucket).
3. Keep the key pair aside; you'll paste the values into Crow.

### GCP — service-account key

1. In the project(s) used by Terraform (`weinbender-io` and
   `remind-me-481700`), create a service account with the roles Terraform needs
   (Artifact Registry, Cloud Run, IAM, workload-identity management).
2. Download its **JSON service-account key** and paste the full JSON contents
   into the Crow secret `gcp_terraform_sa`.

### Cloudflare (unchanged)
Already via 1Password (`op://network/cloudflare-terraform/credential`), plus the
google-oauth client id/secret for the Cloudflare component. Nothing to create.

## Crow repository secrets to set (labs/infrastructure)

The workflow pulls only the credential-bearing values from Crow secrets. The
names are **all lowercase** (Crow lowercases secret names).

| Secret | Value |
|--------|-------|
| `aws_terraform_access_key_id` | access key id from the AWS service account |
| `aws_terraform_secret_access_key` | secret key from the AWS service account |
| `gcp_terraform_sa` | full GCP service-account JSON (single value) |
| `one_password_sa_token` | existing token (unchanged) |

`AWS_DEFAULT_REGION` is **not** a secret: the AWS provider and the S3 state
backend already hardcode `region = "us-east-1"`, so the workflow sets it as a
literal.

`TERRAFORM_APPLY` is **not** a secret either — it is a literal flag in the
workflow file (`.crow/terraform-plan-apply.yaml`), defaulting to `"false"`.
Crow compiles every `from_secret` reference at startup and aborts the whole
pipeline if a referenced secret is missing, so this must be kept as a plain
value rather than a secret.

## What controls plan vs apply

`terraform apply` changes infrastructure, so the workflow defaults to
**plan-only**.

- `TERRAFORM_APPLY: "false"` (default) → run only plans; changes nothing.
- `TERRAFORM_APPLY: "true"` → run also executes `apply -auto-approve`.

Change the literal in `terraform-plan-apply.yaml` to flip this. Storing it as a
workflow literal (not a Crow secret) means the pipeline always compiles without
you having to create an extra secret, and apply stays an explicit, committed
decision.

Launch: Crow -> `labs/infrastructure` -> manual pipeline `Terraform plan/apply
(service account)`.

## Security notes

- Static keys never expire on their own: rotate them on a schedule and revoke
  immediately if ever exposed. Prefer the narrowest permission set for the
  service accounts.
- Secrets are injected only into the Crow step environment and the local,
  uncommitted `.env` is removed at the end of the run — nothing is written to
  Git.
- When you later want keyless auth, the OIDC path (Forgejo Actions as issuer)
  described earlier is the upgrade; keep the key-based flow for now.

## Status

- [x] Crow plan/apply workflow using service-account credentials.
- [x] Docs: this page.
- [ ] Create AWS service-account key (steps above).
- [ ] Create GCP service-account key (steps above).
- [ ] Set Crow secrets (table above).
- [ ] Run one manual pipeline and verify `plan`.

Do not claim the flow works until a manual Crow run returns credentials and a
successful `terraform plan`.