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
| `cloudflare_zone_id` | Cloudflare `weinbender.io` zone ID |
| `cloudflare_account_id` | Cloudflare account ID |

`AWS_DEFAULT_REGION` is **not** a secret: the AWS provider and the S3 state
backend already hardcode `region = "us-east-1"`, so the workflow sets it as a
literal. The Cloudflare zone and account IDs are injected as `TF_VAR_*`
environment variables because the Cloudflare component declares them as
required Terraform inputs.

## What controls plan vs apply

The workflow runs for Terraform changes only:

- Pull request → plan each changed component root; no apply.
- Push to the default branch (including a merge) → plan, then apply each
  changed component root.
- Changes to `terraform/components.json` or shared Terraform root configuration
  select every component. Unrelated files do not select a component.

Each matrix instance checks Crow's `CI_PIPELINE_FILES` list before initializing
Terraform. If Crow omits that variable because more than 500 files changed, the
workflow conservatively selects every component. Crow secrets must be available
to pull-request workflows for PR plans to succeed.

## Security notes

- PR plans run Terraform code from the proposed change with static cloud
  credentials available. Only enable this for trusted contributors and ensure
  Crow's pull-request secret policy is appropriate; Terraform data sources and
  providers can execute code during planning.
- Static keys never expire on their own: rotate them on a schedule and revoke
  immediately if ever exposed. Prefer the narrowest permission set for the
  service accounts.
- Secrets are injected into the Crow step environment; the local `.env` and
  Google service-account file are uncommitted and removed after the run.
- When you later want keyless auth, the OIDC path (Forgejo Actions as issuer)
  described earlier is the upgrade; keep the key-based flow for now.

## Status

- [x] Crow plan/apply workflow using service-account credentials.
- [x] Docs: this page.
- [ ] Create AWS service-account key (steps above).
- [ ] Create GCP service-account key (steps above).
- [ ] Set Crow secrets (table above).
- [ ] Verify a pull-request plan and a default-branch merge plan/apply in Crow.

Do not claim the flow works until Crow successfully plans a PR and applies a
changed root after it is merged to the default branch.
