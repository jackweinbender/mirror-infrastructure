# GitHub Actions workflows

## Compose deployment workflows

`deploy.yaml` is named **Compose stack deployments**. A push to `main` touching any path under `compose-stacks/**`, `ansible/inventory.yaml`, or the workflow runs a complete reconciliation. A daily schedule runs at 05:00 UTC, and `workflow_dispatch` runs the same complete reconciliation with no required inputs.

A preflight job first reads `ansible/inventory.yaml` with the repository’s lightweight Ruby YAML parser and selects workload hosts with `host_roles: deploy`. It validates host and stack names (`^[a-z0-9][a-z0-9_-]*$`), assignment filenames, dotenv syntax, unknown hosts, reserved `docker-host`, and every assigned Compose file using representative values. No SSH connection occurs until preflight succeeds. The workflow first reconciles the `docker-host` platform on every discovered host and waits for the entire platform matrix to complete, then starts one application matrix job per host with stacks processed sequentially. Jobs use `docker-host-<short-host>` concurrency groups and do not cancel an in-progress deployment.

Assigned stacks merge `deployments/_shared.env` and `deployments/<host>.env`, resolve `op://` references with 1Password, stage privately, validate quietly, publish, and run Compose with a stable project name. Failed stacks are recorded while remaining stacks on that host are attempted; the host job fails at the end. Unassigned stacks are torn down before their marked remote directories are removed. Connectivity failures and failed teardowns never trigger cleanup. Entirely deleted local stacks are not automatically pruned.

The workflow owns the Traefik platform and external `proxy` network as well as application stacks. Every run first copies and reconciles `docker-host` on all deploy hosts in parallel, waits for the complete platform matrix, and only then reconciles application stacks. The platform is copied to every host; when `docker-compose.<host>.yaml` exists, it is staged as Compose's conventional `docker-compose.override.yaml`. The `traefik-lxc` override mounts its additional external-service routes there.

## Secrets and trust boundary

Required deployment secrets are `ONE_PASSWORD_SA_TOKEN` and the Tailscale OAuth credentials referenced through 1Password. Runners connect to hosts over the trusted Tailscale network using OpenSSH; `ssh-keyscan -H` populates runner `known_hosts`. Resolved environment values are streamed to remote staging, never printed, passed as arguments, or uploaded as artifacts.

Other workflows cover Terraform planning/apply and Ansible maintenance. Ansible prepares the `deploy` account, Docker access, rsync, and `/etc/compose-stacks`.
