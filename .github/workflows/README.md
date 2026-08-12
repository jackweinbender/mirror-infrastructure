# GitHub Actions workflows

## Compose deployment workflows

`deploy.yaml` is named **Compose stack deployments**. A push to `main` touching application paths under `compose-stacks/**` (excluding `compose-stacks/docker-host/**`), `ansible/inventory.yaml`, or the workflow runs a complete reconciliation; `workflow_dispatch` runs the same complete reconciliation and has no required inputs.

A preflight job first reads the parsed Ansible inventory and selects workload hosts with `host_roles: deploy`. It validates host and stack names (`^[a-z0-9][a-z0-9_-]*$`), assignment filenames, dotenv syntax, unknown hosts, reserved `docker-host`, and every assigned Compose file using representative values. No SSH connection occurs until preflight succeeds. One matrix job is created per discovered host, with stacks processed sequentially. Jobs use `docker-host-<short-host>` concurrency groups and do not cancel an in-progress deployment.

Assigned stacks merge `deployments/_shared.env` and `deployments/<host>.env`, resolve `op://` references with 1Password, stage privately, validate quietly, publish, and run Compose with a stable project name. Failed stacks are recorded while remaining stacks on that host are attempted; the host job fails at the end. Unassigned stacks are torn down before their marked remote directories are removed. Connectivity failures and failed teardowns never trigger cleanup. Entirely deleted local stacks are not automatically pruned.

`deploy-docker-platform.yaml` remains separate and owns Traefik and the external `proxy` network. A push affecting `compose-stacks/docker-host/**` (or the inventory/workflow) discovers every workload host with `host_roles: deploy` and deploys the platform to all of them in parallel, with one serialized job per host. Manual dispatch can still target one host. It uses the same host concurrency groups as the application workflow. Deploy the platform before assigning application stacks that require `proxy`.

## Secrets and trust boundary

Required deployment secrets are `ONE_PASSWORD_SA_TOKEN` and the Tailscale OAuth credentials referenced through 1Password. Runners connect to hosts over the trusted Tailscale network using OpenSSH; `ssh-keyscan -H` populates runner `known_hosts`. Resolved environment values are streamed to remote staging, never printed, passed as arguments, or uploaded as artifacts.

Other workflows cover Terraform planning/apply and Ansible maintenance. Ansible prepares the `deploy` account, Docker access, rsync, and `/etc/compose-stacks`.
