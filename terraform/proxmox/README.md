# terraform/proxmox

Proxmox VE resources — VMs, LXC containers, and related infrastructure on self-hosted Proxmox.

## Resources

Defined in `main.tf` (or split as needed):
- VMs / LXC containers
- Networks, storage, snapshots
- Cloud-init configs

## State Backend

S3 bucket `tf-backend-61rckk`, key `proxmox.tfstate`.

## Auth

Proxmox API token from 1Password:
- `op://network/proxmox-terraform/api-token`
- `op://network/proxmox-terraform/endpoint`

Injected at runtime by `tf-plan-apply` action.

## Provider

`bpg/proxmox` v0.111+

## Deploy

```bash
cd terraform/proxmox
terraform init
terraform plan
terraform apply
```

Or via CI: push to `main` → plan; `workflow_dispatch` with `apply=true` → apply.