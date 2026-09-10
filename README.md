# labs/infrastructure

Personal infrastructure as code. The repository manages cloud resources with
Terraform, configures Debian and Proxmox hosts with Ansible, and deploys
<<<<<<< HEAD
self-hosted services with Docker Compose through self-hosted Crow-CI. This repo
is hosted locally at ssh://git@git.weinbender.io:2222/labs/infrastructure.git and
is mirrored to github at git@github.com:jackweinbender/mirror-infrastructure.git

## Repository Layout

```text
ansible/                 Debian host configuration and Proxmox bootstrap
compose-stacks/          Docker Compose projects and host assignments
terraform/               Independent cloud and virtualization components
.crow/                   Crow CI, validation, and deployment pipelines
scripts/                Ruby CI entrypoints, reusable libraries, and tests
```

Each area has more focused guidance:

- [`ansible/README.md`](ansible/README.md) — host model, playbooks, setup, and
  Molecule tests
- [`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md) — stack layout,
  assignments, deployment lifecycle, and recovery
- [`terraform/`](terraform/) — component-specific READMEs and state boundaries
- [`.crow/`](.crow/) — CI, validation, and deployment pipelines

## Delivery model

| Area | Pipeline | Trigger | Effect |
| --- | --- | --- | --- |
| Ansible | [`.crow/ansible.yaml`](.crow/ansible.yaml) | Scheduled or manual | Lints and applies `playbooks/workloads.yaml` |
| Terraform | [`.crow/terraform-validation.yaml`](.crow/terraform-validation.yaml) | Pull requests, pushes, or manual runs | Validates Terraform components and formatting |
| Terraform | [`.crow/terraform-plan-apply.yaml`](.crow/terraform-plan-apply.yaml) | Manual | Plans or optionally applies each component |
| Compose | [`.crow/deploy.yaml`](.crow/deploy.yaml) | Scheduled or manual | Reconciles the platform and assigned application stacks |
| Repository | [`.crow/repository-validation.yaml`](.crow/repository-validation.yaml) | Push, pull request, or manual | Checks Ruby syntax, tests, preflight, and repository whitespace |

Terraform components are listed in [`terraform/components.json`](terraform/components.json)
and validated against the Terraform root directories.

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
`docker`. LXC persistent data follows the host-backed
`/primary/guest-volumes/<hostname>` to guest `/srv/guest-volumes` convention;
`mp0` is reserved for that mount. VMs are the exception: `docker-vm-dmz` keeps
Docker data in `/var/lib/docker` and requires whole-VM or separate offsite
backups. Tailscale SSH is the supported remote access path; the Proxmox console
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
ruby scripts/preflight.rb

# Ruby automation libraries and entrypoints
ruby scripts/test/lib_test.rb
for script in scripts/*.rb scripts/lib/*.rb scripts/test/*.rb; do
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
