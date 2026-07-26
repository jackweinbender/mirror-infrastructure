# terraform/gcp-weinbender-io

GCP resources for **weinbender.io** — Artifact Registry, IAM, Workload Identity Federation.

## Resources

| File | Resources |
|------|-----------|
| `project.tf` | Project `weinbender-io`, billing |
| `services.tf` | Enable APIs: Artifact Registry, IAM, Cloud Run, etc. |
| `artifact-registry.tf` | Docker repos: `releases` (prod), `nonprod` (dev) |
| `iam.tf` | Service accounts, IAM bindings |
| `workload-identity-federation.tf` | WIF pool + provider for GitHub Actions (`jackweinbender` org) |

## Artifact Registry

| Repo | Location | Format | Purpose |
|------|----------|--------|---------|
| `releases` | `us` | DOCKER | Production container images |
| `nonprod` | `us` | DOCKER | Development/feature images |

Both grant `roles/artifactregistry.reader` to Cloud Run service agent (`service-13264350760@serverless-robot-prod.iam.gserviceaccount.com`).

## Workload Identity Federation

Pool: `github-actions-pool`  
Provider: `gha-jackweinbender`  
Condition: `assertion.repository_owner == 'jackweinbender'`

Maps GitHub OIDC token → GCP service account. Used by CI for Terraform apply and Cloud Run deploy.

## Backend

S3: `tf-backend-61rckk` / `gcp-weinbender-io.tfstate`

## Deploy

```bash
cd terraform/gcp-weinbender-io
terraform init
terraform plan
terraform apply
```

## CI Variables

Set in GitHub repo vars:
- `GCP_WORKLOAD_IDENTITY_PROVIDER` — e.g., `projects/123/locations/global/workloadIdentityPools/github-actions-pool/providers/gha-jackweinbender`
- `GCP_SERVICE_ACCOUNT` — e.g., `github-actions@weinbender-io.iam.gserviceaccount.com`