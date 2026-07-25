# Infrastructure Repository – Copilot Instructions

This monorepo manages home lab infrastructure-as-code. Key components:

## Structure

- **/terraform/**: Infrastructure provisioning (AWS, backend state, Proxmox)

## Coding Guidelines

### Terraform

- Use hyphenated resource names (e.g., `aws-instance-name`).
- Always add `tags` with `Project = "infrastructure/component"`.
- Store sensitive values in `terraform.tfvars` (gitignored).
- Provider auth is env-var driven per component, exported by the
  `tf-plan-apply` composite action from 1Password (e.g.
  `CLOUDFLARE_API_TOKEN`, `PROXMOX_VE_API_TOKEN`/`PROXMOX_VE_ENDPOINT`) —
  never hardcode credentials in `.tf` files.


## Security Considerations

- Legacy: Ansible Vault
- SSH: Managed via GitHub
- Network: Tailscale mesh VPN

## Environment Context

- OS: Ubuntu/Debian
- Monitoring: systemd/journald

**Prioritize simplicity, maintainability, and cost-effectiveness for home lab use.**
