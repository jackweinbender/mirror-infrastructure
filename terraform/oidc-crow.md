# Terraform cloud authentication over OIDC (Crow CI)

This document is the scaffold for giving the **Crow** Terraform pipeline an
OIDC-based path to short-lived AWS and GCP credentials, so Terraform `plan` and
`apply` can run without long-lived cloud secrets. The GitHub Actions path already
has this working; this page is about extending the same trust model to Crow.

## The core constraint: Crow does not mint ID tokens

Crow CI does not provide a native OIDC/JWT ID-token endpoint. Its workflow
environment exposes only `CI_*` / `CROW_*` variables (see
https://crowci.dev/dev/usage/env-vars-usage). OIDC ID-token issuance lives in
**Forgejo Actions** (`enable-openid-connect: true` -> `ACTIONS_ID_TOKEN_REQUEST_URL`
/ `ACTIONS_ID_TOKEN_REQUEST_TOKEN`) and in GitHub Actions (`permissions:
id-token: write`).

That means **an IdP / trust relationship must be supplied before a Crow
Terraform `plan`/`apply` can authenticate to AWS or GCP.** The CI plumbing in
this change assumes the ID token arrives in the step as `OIDC_ID_TOKEN` (see
`.crow/terraform-oidc.yaml`). How that token is produced is the prerequisite you
provide. There are two realistic options.

## Option A — use Forgejo Actions itself as the IdP (recommended)

Forgejo already issues ID tokens for its own Actions runtime. The repository
already carries a Forgejo Actions Terraform workflow with
`enable-openid-connect: true` (`.forgejo/workflows/terraform.yml`), so this path
needs **no extra IdP**, only a trust relationship on the cloud side:

1. Keep the OIDC token request in Forgejo Actions and exchange it for cloud
   credentials there, or
2. Run the credential helper in a workflow/job that has access to
   `ACTIONS_ID_TOKEN_REQUEST_URL` / `ACTIONS_ID_TOKEN_REQUEST_TOKEN` and let it
   bootstrap the Crow step.

The token's `iss` will be your Forgejo instance
(`https://git.weinbender.io/...`). Configure AWS/GCP as below, using the Forgejo
issuer instead of GitHub's `https://token.actions.githubusercontent.com`.

## Option B — bring an external IdP / token broker for Crow (what "provide an IdP" means)

Stand up a small service (delegated credentials / GitHub-style token broker) that:

- is reachable from `ci-base` images,
- authenticates the Crow run (e.g. via a per-repo Crow secret already wired in
  `.crow/terraform-oidc.yaml`, or a Forgejo-issued token),
- returns a short-lived, signed JWT ID token (a valid OIDC `id_token`) carrying
  the cloud trust claims the features below assert,
- exposes an OIDC discovery + JWKS endpoint so AWS and GCP can validate
  signatures.

Whatever you choose, the ID token must be injected into the Crow step as
`OIDC_ID_TOKEN`. See the "Inputs the step needs" section.

## What must be configured on the cloud side (the trust relationship)

AWS and GCP each validate the ID token (`iss`, `aud`, `sub`) and only exchange it
for credentials when the run matches a scoped trust rule. Configure the **same
claims** regardless of Option A or B; only the `iss` changes.

### AWS

1. Create an IAM **OIDC provider** in the account `325498355308` with:
   - Provider URL = your OpenID issuer (Forgejo: `https://git.weinbender.io/`,
     or your IdP's issuer)
   - Audience / client id = the `aud` you choose for the token
   - Thumbprint from the issuer's signing certificate
2. Give the Terraform role `arn:aws:iam::325498355308:role/GithubActionsRole`
   (or a new `CrowTerraformRole`) a federation trust policy scored to the Crow
   run. Constrain with `sub` such as
   `repo:weinbender/labs/infrastructure:ref:refs/heads/main` and a narrow `aud`.
   Do not trust the issuer broadly.
3. The exchange happens at the AWS STS endpoint; the helper posts
   `Action=GetFederationToken` with the ID token as `WebIdentityToken` and the
   role ARN.

### GCP

1. In `terraform/gcp-weinbender-io`, the existing workload identity pool is
   `github-actions-pool` with provider `gha-jackweinbender`
   (`iss = https://token.actions.githubusercontent.com`). Add a **sibling
   provider** in the same pool for the Crow issuer, e.g.:

   ```hcl
   resource "google_iam_workload_identity_pool_provider" "crow" {
     workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
     workload_identity_pool_provider_id = "crow-weinbender-labs"
     display_name                       = "crow-weinbender-labs"
     description                        = "Crow CI identity pool provider for labs infrastructure"
     attribute_condition                = "assertion.repository_owner == 'weinbender'"
     attribute_mapping = {
       "google.subject"             = "assertion.sub"
       "attribute.actor"            = "assertion.actor"
       "attribute.aud"              = "assertion.aud"
       "attribute.repository"       = "assertion.repository"
       "attribute.repository_owner" = "assertion.repository_owner"
     }
     oidc {
       issuer_uri = "<your issuer uri>"   # Forgejo: https://git.weinbender.io/
     }
   }
   ```

   (a) Adjust `issuer_uri`, `attribute_condition`, and any `aud` mapping to the
   claims your IdP mints; (b) this is declared here for the review, and only
   takes effect once the environment / plan apply is run for that component.

2. The exchange uses GCP token exchange (`grant_type=token-exchange`,
   `audience` = the full pool-provider resource name such as
   `projects/<project>/locations/global/workloadIdentityPools/github-actions-pool/providers/crow-weinbender-labs`).

## Inputs the step needs (Crow variables / secrets)

| Name | Purpose | Provided by |
|------|---------|-------------|
| `OIDC_ID_TOKEN` | The short-lived ID token for the run | the IdP / broker you stand up (Option B), or a bridge from Forgejo Actions (Option A) |
| `AWS_TERRAFORM_ROLE_ARN` (or reuse `AWS_ROLE_TO_ASSUME`) | Role the STS exchange returns | repository / Crow variable |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full pool-provider resource name | repo value / Crow variable (existing `vars.GCP_WORKLOAD_IDENTITY_PROVIDER`) |
| `GCP_SERVICE_ACCOUNT` | Service account email to impersonate | repo value |
| `ONE_PASSWORD_SA_TOKEN` | Cloudflare + google-oauth secrets via 1Password | existing Crow secret |

## How this repo's helper is used

- `.github/scripts/lib/oidc_cloud_auth.rb` — pure, tested pieces (build AWS env
  from an STS response, shape the AWS STS and GCP token-exchange requests, merge
  into a cloud environment hash).
- `.github/scripts/oidc-cloud-auth.rb` — thin entrypoint: reads `OIDC_ID_TOKEN`
  from the environment, calls the library, writes an exportable `KEY=VALUE`
  block for the cloud credentials to a file the workflow sources.
- `.crow/terraform-oidc.yaml` — manual Crow plan/apply pipeline that calls the
  auth entrypoint, loads 1Password secrets, and runs `init` / `fmt` / `validate`
  / `plan` (and `apply` only when explicitly dispatched).

## Status

- [x] OIDC auth helper + tests, Crow workflow scaffold, this runbook.
- [ ] IdP / issuer provided (Option A or B).
- [ ] AWS OIDC provider + role trust policy.
- [ ] GCP workload identity pool/provider for the Crow issuer (requires a plan
      apply of `gcp-weinbender-io`).
- [ ] Live Crow `plan` verified end-to-end; `apply` remains manual-only.

Do not claim the OIDC flow works until a real ID token from the chosen issuer
successfully returns AWS/GCP credentials in a Crow run.