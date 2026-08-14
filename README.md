# jackweinbender/infrastructure

Personal infrastructure as code. The repository manages cloud resources with
Terraform, configures Debian and Proxmox hosts with Ansible, and deploys
self-hosted services with Docker Compose through GitHub Actions.

## Repository Layout

```text
ansible/                 Debian host configuration and Proxmox bootstrap
compose-stacks/          Docker Compose projects and host assignments
terraform/               Independent cloud and virtualization components
.github/
  scripts/               Ruby workflow entrypoints, reusable libraries, and tests
  workflows/             CI, validation, and deployment workflows
```

Each area has more focused guidance:

- [`ansible/README.md`](ansible/README.md) — host model, playbooks, setup, and
  Molecule tests
- [`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md) — stack layout,
  assignments, deployment lifecycle, and recovery
- [`terraform/`](terraform/) — component-specific READMEs and state boundaries
- [`.github/workflows/README.md`](.github/workflows/README.md) — workflow
  orchestration, triggers, and deployment safety

## Delivery model

| Area | Workflow | Trigger | Effect |
| --- | --- | --- | --- |
| Ansible | [`main-ansible.yaml`](.github/workflows/main-ansible.yaml) | Pushes to `main` affecting `ansible/**`, daily at 04:00 UTC, or manual dispatch | Lints and applies `playbooks/workloads.yaml` |
| Terraform | [`pr-plan-all.yml`](.github/workflows/pr-plan-all.yml) | Pull requests affecting Terraform or its automation | Validates changed components and posts plan comments; never applies |
| Terraform | [`main-plan-apply-all.yml`](.github/workflows/main-plan-apply-all.yml) | Pushes to `main` affecting `terraform/**`, or manual dispatch | Plans and applies all components; manual runs can be plan-only |
| Terraform | [`plan-or-apply.yml`](.github/workflows/plan-or-apply.yml) | Manual dispatch on `main` | Plans or optionally applies one selected component |
| Compose | [`deploy.yaml`](.github/workflows/deploy.yaml) | Pushes to `main` affecting Compose/inventory/deployment workflow, daily at 05:00 UTC, or manual dispatch | Reconciles the platform and assigned application stacks |
| GitHub automation | [`validate-github-automation.yml`](.github/workflows/validate-github-automation.yml) | Pull requests affecting workflows or Ruby scripts | Runs actionlint, Ruby syntax checks, and library tests |

The Terraform workflows call the reusable implementation in
[`terraform.yml`](.github/workflows/terraform.yml). Terraform components are
listed in [`.github/terraform-components.json`](.github/terraform-components.json)
and must remain synchronized with the manual workflow choices.

## Compose deployments

Compose deployment has two layers:

1. **Platform:** `compose-stacks/docker-networking/` owns the external `proxy`
   network and is reconciled on every inventory host with `host_roles: deploy`.
2. **Applications:** every other stack—including Traefik—is assigned explicitly
   through `deployments/<host>/.env.template` and is reconciled only on hosts
   where it is assigned.

`deploy.yaml` validates the inventory, assignments, dotenv templates, overlays,
and Compose files before making an SSH connection. It then:

1. Reconciles `docker-networking` on every deploy host.
2. Waits for all platform jobs to succeed.
3. Reconciles assigned application stacks on each host.

Deployments connect over Tailscale, stage privately on the remote host, inject
1Password-backed environment values directly into remote staging, validate with
`docker compose config --quiet`, and publish only marked managed directories.
Resolved secrets are not committed, printed, passed as command-line arguments,
or stored on the GitHub runner.

Read [`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md) before adding
or moving a stack. In particular, do not add a `deployments/ALL/` assignment, do
not let application stacks manage `proxy`, and do not remove an unmarked remote
directory during recovery.

## Terraform state and credentials

Terraform components keep their own state boundaries and backend configuration.
The AWS component uses the S3 backend bucket `tf-backend-61rckk` in
`us-east-1`; other backend settings are defined by their component. CI uses
GitHub OIDC for AWS and GCP where configured and 1Password-backed credentials
for secrets. Never commit state, plans containing secrets, provider credentials,
private keys, or resolved secret values.

## Ansible

Ansible supports Debian guests and Proxmox bootstrap workflows. The steady-state
`playbooks/workloads.yaml` playbook always applies the baseline roles and then
selects additional roles from each host's `host_roles`, such as `deploy` and
`docker`. Tailscale SSH is the supported remote access path; the Proxmox console
is the bootstrap recovery path.

Set up the local environment with:

```bash
cd ansible
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/ansible-playbook playbooks/workloads.yaml
```

Review inventory, limits, and tags before running a playbook that can change a
remote host. See [`ansible/README.md`](ansible/README.md) for bootstrap commands
and validation.

## Local validation

Run the checks relevant to the area you changed. From the repository root:

```bash
# Compose inventory, assignments, dotenv templates, and Compose files
ruby .github/scripts/preflight.rb

# Ruby automation libraries and entrypoints
ruby .github/scripts/test/lib_test.rb
for script in .github/scripts/*.rb .github/scripts/lib/*.rb .github/scripts/test/*.rb; do
  ruby -c "$script" || exit 1
done

# All changed files
git diff --check
```

For Terraform, run `terraform fmt -check`, `terraform init -backend=false`, and
`terraform validate` from the changed component. For Ansible, use the project
virtual environment and run `ansible-lint` plus playbook syntax checks. For a
Compose change, also run a representative `docker compose ... config --quiet`
command as described in the operations runbook.

Do not run `terraform apply` or production/bootstrap playbooks locally unless the
change explicitly authorizes it and the target, inventory, and limits have been
reviewed.
