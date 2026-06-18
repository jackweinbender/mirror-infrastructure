# Infrastructure Repository – Copilot Instructions

This monorepo manages home lab infrastructure-as-code. Key components:

## Structure

- **/terraform/**: Infrastructure provisioning (AWS, backend state)

## Coding Guidelines

### Terraform

- Use hyphenated resource names (e.g., `aws-instance-name`).
- Always add `tags` with `Project = "infrastructure/component"`.
- Store sensitive values in `terraform.tfvars` (gitignored).


## Security Considerations

- Legacy: Ansible Vault
- SSH: Managed via GitHub
- Network: Tailscale mesh VPN

## Environment Context

- OS: Ubuntu/Debian
- Monitoring: systemd/journald

**Prioritize simplicity, maintainability, and cost-effectiveness for home lab use.**
