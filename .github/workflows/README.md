# .github/workflows

GitHub Actions CI/CD pipelines for this infrastructure repo.

## Workflows

| File | Trigger | Purpose |
|------|---------|---------|
| `pr-plan-all.yml` | Pull request | `terraform plan` for all components (no apply) |
| `main-plan-apply-all.yml` | Push to `main`, `workflow_dispatch` | Plan all components on push; apply on manual dispatch |
| `main-plan-apply.yml` | Push to `main` (paths), `workflow_dispatch` | Plan/apply single component |
| `deploy-docker-platform.yaml` | `workflow_dispatch` | Deploy/maintain Traefik and the shared Docker network on a host |
| `deploy.yaml` | `workflow_dispatch` | Deploy application compose stacks to VMs via Tailscale |

## pr-plan-all.yml

- Runs on PRs touching `terraform/**`
- Matrix: `mgmt, aws, gcp-remind-me, gcp-weinbender-io, cloudflare, proxmox`
- Uses `tf-plan-apply` action with `apply: false`
- Posts plan summary as PR comment

## main-plan-apply-all.yml

- Runs on push to `main` (always plan)
- `workflow_dispatch` input `apply: boolean` (default false) — if true, applies all
- Same matrix as pr-plan-all
- Requires `id-token: write` for OIDC

## main-plan-apply.yml

- Path-filtered: triggers on `terraform/<component>/**` changes
- Single component per run
- `workflow_dispatch` with `component` + `apply` inputs

## deploy-docker-platform.yaml

- Manual `workflow_dispatch` only
- Provides a `host` dropdown (`docker-vm-dmz` or `docker0-lxc`) and `user` (default: `deploy`)
- `DOCKER_USER` can override the default SSH user
- Creates the attachable external `proxy` network idempotently
- Steps: validate → Tailscale → rsync → inject secrets on host → `docker compose up`
- Repeat the workflow for each Docker host. Ansible prepares the host; this workflow deploys the platform.

## deploy.yaml

- Manual only (`workflow_dispatch`)
- Inputs: `stack` (homeassistant|public-gateway), `host` (Tailscale MagicDNS), `user` (default: `deploy`)
- Steps: validate → rsync → inject secrets (1Password) → docker compose up

## Secrets Required

| Secret | Workflows |
|--------|-----------|
| `ONE_PASSWORD_SA_TOKEN` | All Terraform + deploy |
| `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_CLIENT_SECRET` | All (Tailscale) |
| `CLOUDFLARE_ZONE_ID` / `CLOUDFLARE_ACCOUNT_ID` | Terraform (Cloudflare) |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_SERVICE_ACCOUNT` | Terraform (GCP) |

## OIDC Providers

| Cloud | Role / Pool |
|-------|-------------|
| AWS | `arn:aws:iam::325498355308:role/GithubActionsRole` |
| GCP | WIF pool `github-actions-pool`, provider `gha-jackweinbender` |

## Composite Action: tf-plan-apply

Located at `.github/actions/tf-plan-apply/action.yml`. Reusable step:
- Loads 1Password secrets → env
- Tailscale connect
- `terraform init/fmt/validate/plan`
- Optional `apply` if input `apply == 'true'`