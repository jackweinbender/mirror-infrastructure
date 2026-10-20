# labs/infrastructure

Personal infrastructure as code. The repository manages cloud resources with
Terraform, configures Debian and Proxmox hosts with Ansible, and maintains
Docker Compose services. CI validates Compose configuration but does not deploy
it. Each host enabled for deployment runs exactly one c5e controller, which
reconciles only that host's assignments through its local Docker daemon.
The repository is hosted locally at
ssh://git@forgejo.weinbender.io:2222/labs/infrastructure.git and mirrored to
GitHub at git@github.com:jackweinbender/mirror-infrastructure.git.

## Repository Layout

```text
ansible/                 Debian host configuration and Proxmox bootstrap
compose-stacks/          Docker Compose projects and host assignments
terraform/               Independent cloud and virtualization components
.crow/                   Crow CI, validation, and infrastructure deployment pipelines
scripts/                Ruby CI entrypoints, reusable libraries, and tests
```

Each area has more focused guidance:

- [`ansible/README.md`](ansible/README.md) — host model, playbooks, setup, and
  Molecule tests
- [`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md) — stack layout,
  assignments, deployment lifecycle, and recovery
- [`terraform/`](terraform/) — component-specific READMEs and state boundaries
- [`.crow/`](.crow/) — CI, validation, and infrastructure deployment pipelines

## Delivery model

| Area | Pipeline | Trigger | Effect |
| --- | --- | --- | --- |
| Ansible | [`.crow/ansible.yaml`](.crow/ansible.yaml) | Relevant default-branch pushes, scheduled, or manual | Runs the full `site.yaml` on pushes/schedule; manual runs select a steady-state profile; no PR host changes |
| Ansible validation | [`.crow/ansible-validation.yaml`](.crow/ansible-validation.yaml) | Relevant pull requests, default-branch pushes, or manual | Lints Ansible and checks playbook syntax |
| Terraform validation | [`.crow/terraform-validation.yaml`](.crow/terraform-validation.yaml) | Relevant pull requests, default-branch pushes, or manual | Validates Terraform components and formatting |
| Terraform plan/apply | [`.crow/terraform-plan-apply.yaml`](.crow/terraform-plan-apply.yaml) | Pull requests and default-branch pushes affecting Terraform | Plans changed roots on PRs; plans and applies changed roots on the default branch |
| Compose validation | [`.crow/compose-validation.yaml`](.crow/compose-validation.yaml) | Relevant pull requests, default-branch pushes, or manual | Checks inventory, assignments, templates, and Compose files |
| CI images | [`.crow/ci-base.yaml`](.crow/ci-base.yaml) | Relevant default-branch pushes or manual | Builds and publishes the CI images |
| Repository validation | [`.crow/repository-validation.yaml`](.crow/repository-validation.yaml) | Default-branch pushes, pull requests, or manual | Checks Ruby syntax, tests, preflight, and repository whitespace |

Manual runs of `.crow/ansible.yaml` expose an `ANSIBLE_PLAYBOOK` dropdown:
`site.yaml` composes both profiles; `debian-host-ops.yaml` configures the
`debian_hosts` profile; `stack-hosts.yaml` configures container and deployment
capabilities. The default is `site.yaml`. Default-branch pushes and the schedule
always run full `site.yaml` convergence. The separate validation workflow checks
playbook syntax without changing hosts; bootstrap and Proxmox workflows remain
operator-run.

Terraform components are listed in [`terraform/components.json`](terraform/components.json)
and validated against the Terraform root directories.

## Compose deployments

Every Compose stack is an application stack, assigned explicitly through
`deployments/<inventory_hostname_short>/.env.template`. This directory name must
exactly match the host's `inventory_hostname_short`. `deployment_hosts` is the
deployment-capable subset of `stack_hosts` and is the only group eligible for
application assignments; other groups do not grant assignment eligibility.
Each deployment host has exactly one c5e controller using its local Docker daemon.
c5e provides that host's external `proxy` network before reconciling its
assigned applications; there is no `docker-networking` platform stack.

Current deployment assignment hosts are `traefik-lxc`, `docker0-lxc`,
`docker-vm-dmz`, and `lxc-docker-core0`. A host is listed here because Compose
assignment directories target it; other configured services without assignment
directories are not deployed by this repository's Compose assignments.

The `.crow/compose-validation.yaml` pipeline validates Compose inventory,
assignments, templates, and files; it does not deploy stacks. Initialize each
controller on its own host with that host's credentials, inspecting that host's
local network and daemon IDs. Never reuse one credential/network-ID pair across
hosts. Initialization is targeted to an individual host, not fleet-wide. Keep
resolved secrets out of Git, logs, and runner artifacts. c5e does not
automatically adopt existing Docker resources by project name: foreign or mixed
ownership blocks Up/Down, and historical automation markers do not grant
adoption permission.
Its `retain` policy leaves removed assignments and orphaned projects in place.
Do not imply an operational rollout or live-stack handoff as part of an
assignment change; preserve safe remote-state handling and do not remove live
directories without establishing that it is safe.

Read [`compose-stacks/OPERATIONS.md`](compose-stacks/OPERATIONS.md) before adding
or moving a stack. Never add a `deployments/ALL/` assignment or let application
stacks manage the c5e-provided `proxy` network.

## Terraform state and credentials

Terraform components keep their own state boundaries and backend configuration.
The AWS component uses the S3 backend bucket `tf-backend-61rckk` in
`us-east-1`; other backend settings are defined by their component. CI uses
static service-account credentials for AWS and GCP managed as Crow secrets and
1Password-backed credentials for secrets. Never commit state, plans containing
secrets, provider credentials, private keys, or resolved secret values.

Ansible supports Debian guests and Proxmox bootstrap workflows. The steady-state
`playbooks/site.yaml` composes the Debian host-operations and stack-host profiles.
Inventory groups describe host populations; playbooks compose capabilities such
as logging, Docker/Compose, and c5e deployment.
LXC persistent data follows the host-backed `/primary/guest-volumes/<hostname>`
to guest `/srv/guest-volumes` convention; `mp0` is reserved for that mount.
VMs are the exception: `docker-vm-dmz` keeps Docker data in `/var/lib/docker`
and requires whole-VM or separate offsite backups. Tailscale SSH is the
supported remote access path; the Proxmox console is the bootstrap recovery
path. The c5e dashboard is deliberately loopback-only at `127.0.0.1:8080`;
Ansible retires only its c5e-labeled Compose service after verifying ownership.

Set up the local environment with:

```bash
cd ansible
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/ansible-playbook playbooks/site.yaml
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
