---
name: terraform-components
description: Maintain this repository's isolated Terraform cloud and Proxmox components with safe state boundaries, provider-specific DNS and ingress conventions, plan-first changes, and CI-compatible validation.
---

# Terraform components

Use this skill for changes under `terraform/`, component selection in GitHub
Actions, state/backend changes, provider resources, or plan/apply decisions. Read
`terraform/AGENTS.md`, `terraform/README.md`, and the changed component README
first.

## Preserve component boundaries

- Each `terraform/<component>/` directory is an independent component with its
  own state key and backend. Do not move resources between components or change
  backend identity casually.
- Keep provider, variable, output, and backend conventions local to the component.
- Keep component names synchronized with `terraform/components.json` and
  the Crow component matrix.
- Prefer plan-only validation. Apply only when explicitly requested or through
  the intended workflow.

## Cloudflare ingress and DNS

Before adding a DNS record, check the Cloudflare dashboard: `dns.tf` contains only
the Terraform-managed subset, while many zone records remain managed manually.
Choose the ingress path explicitly:

- Tunnel-backed services use a CNAME directly to the tunnel target.
- Services behind a LAN Traefik gateway require both an unproxied gateway A record
  (`<gateway>.weinbender.io` to its private LAN IPv4 address) and an unproxied
  service CNAME (`<service>.weinbender.io` to the gateway hostname).
- The gateway A record is a provisioning follow-up once the gateway LXC address is
  known; it is not an Ansible task. Add service CNAMEs when services are assigned.
- When managed in Terraform, keep the pair in `terraform/cloudflare/dns.tf` with
  `proxied = false` and `ttl = 1`. The service hostname must exactly match the
  Traefik `Host(...)` rule; never substitute a tunnel target for the LAN path.

Cloudflare Access policies and user membership rules documented as dashboard-owned
must remain data-source references rather than Terraform-managed resources.
Provider credentials and OAuth values come from 1Password/runtime CI injection.

## State, credentials, and workflow

Never commit state, plans containing secrets, provider credentials, private keys, or
resolved `op://` values. Preserve AWS OIDC, GCP Workload Identity Federation, and
1Password authentication paths. PR plans are advisory; main workflows are the
controlled path for apply, and manual component workflows must be reviewed for
plan-only versus apply mode.

## Validation

From the changed component directory run:

```bash
terraform fmt -check
terraform init -backend=false
terraform validate
terraform plan
```

Use the component README for provider-specific prerequisites and backend-aware
commands. From the repository root, run the Terraform component manifest check and
`git diff --check`. Do not run `terraform apply` unless the user explicitly
authorizes it; always review the plan before any apply.
