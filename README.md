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
│   ├── docker-networking/  # Shared proxy network deployed to every Docker host
│   ├── traefik/            # Normal assigned Traefik stack
│   └── cloudflare-tunnel/  # Cloudflare Tunnel ingress (uses host Traefik)
└── .github/
    └── workflows/          # CI/CD pipelines and reusable workflows
```

## Deployment

| Layer | Tool | Target | Trigger |
|-------|------|--------|---------|
| Terraform | GitHub Actions (`terraform.yml`) | AWS, Cloudflare, GCP, Proxmox | Push to `main` (plan + apply) / `workflow_dispatch` (plan by default, optional apply) |
| Docker host platform and Compose stacks | GitHub Actions (`deploy.yaml`) | Docker hosts via Tailscale | Push to `main` / daily at 05:00 UTC / `workflow_dispatch` |

### Terraform

- **Advisory plan on PR** — `.github/workflows/pr-plan-all.yml` detects changed components and comments their `terraform plan` output; this is informational only
- **Authoritative plan + apply on merge** — `.github/workflows/main-plan-apply-all.yml` runs a fresh plan and apply on push to `main`; manual dispatch applies by default and can be changed to plan-only
- **Plan or apply one component** — `.github/workflows/plan-or-apply.yml` lets you select the component and whether to apply
- Components are listed in `.github/terraform-components.json`; manual workflow choices mirror that manifest
- Secrets via 1Password (`OP_SERVICE_ACCOUNT_TOKEN`), OIDC for AWS/GCP

### Compose Stacks

The standard stack shape, assignment rules, overlay behavior, validation
commands, and recovery process are documented in
[`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md).

The `deploy.yaml` workflow owns the complete Compose desired state:
1. Every run first creates the shared external `proxy` network if needed and deploys Traefik on every deploy host.
2. After all platform jobs succeed, it syncs assigned application stacks, injects their secrets, and reconciles their Compose projects with Docker.
3. The workflow rsyncs over Tailscale and injects 1Password secrets directly to the remote `.env` — resolved secrets never persist on the runner.

Required secrets: `ONE_PASSWORD_SA_TOKEN`, `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_CLIENT_SECRET`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_ACCOUNT_ID`, GCP WIF vars.

## Backend State

- **AWS**: S3 bucket `tf-backend-61rckk` (us-east-1)
- **Others**: Remote backend configured per-component (see each `terraform.tf`)

### Ansible

Infrastructure configuration and host management via Ansible:
1. Installs baseline configurations (`roles/base/`)
2. Deploys Docker or Tailscale as needed per host
3. Converges hosts to desired state via `playbooks/workloads.yaml`
4. Bootstrap playbooks with interactive menu selection for Proxmox hosts and SSH keys

**Tested with Molecule** — All roles have automated tests that run in Docker containers before touching production.

**Setup**:

```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

For each session, activate the venv before running playbooks:

```bash
cd ansible
source .venv/bin/activate
ansible-playbook playbooks/local-bootstrap-lxc.yaml  # Interactive menus
```

## Testing

### Ansible

All playbooks are syntax-checked and linted. Roles have comprehensive Molecule tests in Docker:

**Setup** (one-time):
```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**Run tests**:
```bash
# Playbook validation
ansible-lint
ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check

# Role unit tests (requires Docker)
cd roles/base && ../../.venv/bin/molecule test
cd roles/docker && ../../.venv/bin/molecule test
cd roles/tailscale && ../../.venv/bin/molecule test
```



### Terraform

- **Plan validation** — `.github/workflows/pr-plan-all.yml` validates all terraform changes on PRs
- **Syntax & format** — `terraform validate` and `terraform fmt` in CI

## Prerequisites

- **Docker** (for running Ansible role tests locally)
- Tailscale OAuth client (for GitHub Actions → VM connectivity)
- 1Password service account (for secret injection)
- GCP Workload Identity Federation configured
- AWS IAM role `GithubActionsRole` (arn:aws:iam::325498355308:role/GithubActionsRole)
- Proxmox API token (stored in 1Password)