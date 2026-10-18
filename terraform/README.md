# terraform/

Multi-cloud Terraform configurations. Each subdirectory is an independent component with its own state backend.

## Components

| Component | Provider(s) | Purpose |
|-----------|-------------|---------|
| `aws/` | AWS | Route53 zone `labs.weinbender.io`, S3 bucket, CloudFront distribution, ACM cert |
| `cloudflare/` | Cloudflare | Zero Trust Access (uk2026.weinbender.io), DNS, Cloudflare Tunnel |
| `gcp-remind-me/` | GCP | Cloud Run services (dev/prod), IAM, Artifact Registry for `remind-me` app |
| `gcp-weinbender-io/` | GCP | Artifact Registry (releases/nonprod), WIF pool for GitHub Actions, IAM bindings |
| `mgmt/` | AWS | Root S3 bucket for Terraform state (`tf-backend-*`) |
| `proxmox/` | Proxmox (bpg/proxmox) | VM/LXC resources on self-hosted Proxmox |

## State Backends

- `mgmt/` creates the S3 bucket used by other components
- `aws/`, `cloudflare/`, `gcp-remind-me/`, `gcp-weinbender-io/`, `proxmox/` use `backend "s3"` pointing to `tf-backend-61rckk` (key per component)

## Authentication

| Provider | Method |
|----------|--------|
| AWS | OIDC → `arn:aws:iam::325498355308:role/GithubActionsRole` |
| GCP | Workload Identity Federation (pool `github-actions-pool`, provider `gha-jackweinbender`) |
| Cloudflare | API token from 1Password (`op://network/cloudflare-terraform/credential`) |
| Proxmox | API token from 1Password (`op://network/proxmox-terraform/api-token`) |

Crow CI runs Terraform through `.crow/terraform-plan-apply.yaml` using static
service-account credentials stored as Crow secrets (no OIDC/IdP). Pull requests
plan changed roots; pushes to the default branch plan and apply changed roots.
Changes to `components.json` or shared Terraform root configuration run every
component. See [`terraform/crow-sa.md`](crow-sa.md) for credential setup and PR
security considerations.

## Usage

```bash
# Local development
cd terraform/<component>
terraform init
terraform plan
terraform apply

# CI/CD: pull requests plan changed roots; pushes to the default branch plan and apply changed roots
```

## Conventions

- One component per subdirectory
- `terraform.tf` declares required_providers + backend
- Variables in `variables.tf`, outputs in `outputs.tf`
- Crow injects static cloud credentials as secrets and resolves 1Password `op://` references at runtime
- No hardcoded secrets — sensitive values come from 1Password or the relevant CI secret store
