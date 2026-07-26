# terraform/gcp-remind-me

GCP resources for the **remind-me** application — Cloud Run services (dev/prod), IAM, APIs.

## Resources

| File | Resources |
|------|-----------|
| `project.tf` | Project `remind-me-app`, billing |
| `services.tf` | Enable APIs: Run, Cloud Build, Artifact Registry, etc. |
| `iam.tf` | Service accounts, IAM bindings |
| `cloudrun-dev.tf` | Cloud Run `remindme-dev` (public, us-central1) |
| `cloudrun-prod.tf` | Cloud Run `remindme-prod` (public, us-central1) |

## Environments

| Env | Service | URL Pattern |
|-----|---------|-------------|
| Dev | `remindme-dev` | `https://remindme-dev-<hash>-uc.a.run.app` |
| Prod | `remindme-prod` | `https://remindme-prod-<hash>-uc.a.run.app` |

Both allow `allUsers` invoker (public).

## Backend

S3: `tf-backend-61rckk` / `gcp-remind-me.tfstate`

## Auth

GCP auth via Workload Identity Federation (configured in `terraform/gcp-weinbender-io/workload-identity-federation.tf`). CI uses:
- `workload_identity_provider` = `vars.GCP_WORKLOAD_IDENTITY_PROVIDER`
- `service_account` = `vars.GCP_SERVICE_ACCOUNT`

## Deploy

```bash
cd terraform/gcp-remind-me
terraform init
terraform plan
terraform apply
```

Container images pushed to Artifact Registry (managed in `terraform/gcp-weinbender-io/`).