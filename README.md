# jackweinbender/infrastructure

Personal infrastructure as code — Terraform for cloud resources + Docker Compose stacks for self-hosted services.

## Structure

```
├── terraform/              # Terraform modules (multi-cloud)
│   ├── aws/                # AWS: Route53, S3, CloudFront, ACM (labs.weinbender.io)
│   ├── cloudflare/         # Cloudflare: Access, DNS, Tunnel
│   ├── gcp-remind-me/      # GCP: Cloud Run (dev/prod), IAM, services (remind-me app)
│   ├── gcp-weinbender-io/  # GCP: Artifact Registry, IAM, WIF (weinbender.io)
│   ├── mgmt/               # Management/root resources
│   └── proxmox/            # Proxmox VE resources
├── compose-stacks/         # Docker Compose stacks (deployed via GitHub Actions → Tailscale → VMs)
│   ├── homeassistant/      # Home Assistant + MQTT + Zigbee2MQTT
│   └── public-gateway/     # Traefik + Cloudflare Tunnel + demo service
└── .github/
    ├── workflows/          # CI/CD pipelines
    └── actions/            # Reusable composite actions (tf-plan-apply)
```

## Deployment

| Layer | Tool | Target | Trigger |
|-------|------|--------|---------|
| Terraform | GitHub Actions (`tf-plan-apply`) | AWS, Cloudflare, GCP, Proxmox | Push to `main` (plan) / `workflow_dispatch` (apply) |
| Compose stacks | GitHub Actions (`deploy.yaml`) | Self-hosted VMs via Tailscale | `workflow_dispatch` |

### Terraform

- **Plan on PR** — `.github/workflows/pr-plan-all.yml` runs `terraform plan` for all components
- **Plan + Apply on merge** — `.github/workflows/main-plan-apply-all.yml` runs plan on push to `main`; apply requires `workflow_dispatch` with `apply: true`
- **Per-component** — `.github/workflows/main-plan-apply.yml` targets a single component
- Secrets via 1Password (`OP_SERVICE_ACCOUNT_TOKEN`), OIDC for AWS/GCP

### Compose Stacks

Deployed via `deploy.yaml`:
1. Validates Home Assistant config (if applicable)
2. Rsyncs stack to target VM over Tailscale
3. Injects secrets from 1Password (`op inject`) directly to remote `.env` — never touches runner disk
4. Runs `docker compose up -d --pull missing`

Required secrets: `ONE_PASSWORD_SA_TOKEN`, `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_CLIENT_SECRET`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_ACCOUNT_ID`, GCP WIF vars.

## Backend State

- **AWS**: S3 bucket `tf-backend-61rckk` (us-east-1)
- **Others**: Remote backend configured per-component (see each `terraform.tf`)

## Prerequisites

- Tailscale OAuth client (for GitHub Actions → VM connectivity)
- 1Password service account (for secret injection)
- GCP Workload Identity Federation configured
- AWS IAM role `GithubActionsRole` (arn:aws:iam::325498355308:role/GithubActionsRole)
- Proxmox API token (stored in 1Password)