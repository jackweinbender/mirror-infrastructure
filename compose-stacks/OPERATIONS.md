# Compose deployment operations

This runbook defines the standard pattern for Docker Compose stacks managed by
GitHub Actions. The workflow is the owner of the desired state; hosts should not
be changed manually except for recovery work described below.

## Architecture

There are two kinds of Compose stack:

- **Platform stack**: `docker-networking` is special. It owns the external
  `proxy` network and is applied to every host with `host_roles: deploy`.
- **Application stack**: every other stack is assigned to hosts by deployment
  directories. Traefik is an application stack, not part of the platform stack.

The deployment order is intentional:

1. Preflight validates inventory, stack names, dotenv templates, assignments,
   overlays, and Compose configuration.
2. `docker-networking` is reconciled on every deploy host.
3. Only after every networking job succeeds, assigned application stacks are
   reconciled on each host.

Application stacks may declare `proxy` as an external network. They must not
create, delete, or otherwise manage that network themselves.

## Standard stack shape

```text
compose-stacks/<stack>/
  docker-compose.yaml
  .env.template                 # optional shared values
  deployments/
    <host>/
      .env.template             # assignment; may contain op:// references
      docker-compose.yaml       # optional host-specific Compose overlay
```

Additional files such as application configuration, certificates, or dynamic
route definitions stay in the stack directory and are copied with the base
Compose project.

### Assignment

The presence of `deployments/<host>/.env.template` assigns the stack to that
exact short host ID from `ansible/inventory.yaml`. An empty template is still an
assignment. The host must have `host_roles: deploy`.

There is no `deployments/ALL/` convention. A stack that belongs everywhere is
handled explicitly by the platform reconciler, as with `docker-networking`.
For an ordinary application stack, enumerate its real assignments.

### Compose overlays

An optional `deployments/<host>/docker-compose.yaml` is used only for an
already-assigned host. The workflow copies it to the staged project as
`docker-compose.override.yaml`, so the same Compose commands work for every
host. An overlay does not assign a stack.

Use an overlay for host-specific mounts, ports, resources, or service settings.
Keep common services and defaults in the root `docker-compose.yaml`.

### Environment templates

Use `.env.template` consistently:

- Root `.env.template` contains values shared by all assignments and is
  optional.
- `deployments/<host>/.env.template` contains host-specific values and is
  required for an application assignment.
- Host-specific values override root values.
- Secret references use `op://...`; resolved secrets must never be committed.

The workflow merges the templates, resolves 1Password references, and writes
only the resolved `.env` to private remote staging. Do not create or commit
runtime `.env` files in the repository.

## Filesystem and bind-mount rules

Docker creates a missing bind-mount source as a directory. A path intended to
be a file must therefore exist in the repository as a regular file before
Compose runs. For example:

```yaml
volumes:
  - ./traefik.yml:/etc/traefik/traefik.yml:ro
```

requires `traefik.yml` to be a file beside `docker-compose.yaml`, not a nested
or missing path. Incorrect paths can produce root-owned directories because
Docker creates bind sources through the Docker daemon. This can both prevent
the service from starting and block the `deploy` user from cleaning up the
stack.

Before opening a change, check every file bind source:

```bash
find compose-stacks/<stack> -type f -print
# Then verify each left-hand bind source in the Compose files is a regular file.
```

Prefer read-only mounts for configuration. A service that must write persistent
state should write to a deliberately designed named volume or data directory,
not into the checked-out Compose project. On LXC deploy hosts explicitly
configured with `docker_configure_data_root: true`, named volumes are stored
below `/srv/guest-volumes/docker`; the LXC mount itself is provisioned by the
local Proxmox bootstrap workflow, not by Compose. Compose does not create
per-stack host directories for named volumes.

`docker-vm-dmz` is a deliberate exception: it is a VM and keeps Docker's data
under the VM-local `/var/lib/docker`. Its persistence therefore depends on
whole-VM backups or a separate offsite backup job. Do not assume the LXC
`/primary/guest-volumes/<hostname>` bind-mount convention applies to VMs.

## Reconciliation lifecycle

For an assigned application stack, the workflow:

1. Merges the root and host `.env.template` files.
2. Creates a private remote staging directory.
3. Rsyncs the stack while excluding runtime environment files and Git data.
4. Installs the optional host overlay.
5. Writes the deployment marker and injects the resolved `.env`.
6. Runs `docker compose config --quiet` in staging.
7. Verifies the existing live directory is managed by this repository.
8. Stops the old project, publishes the staged directory, and runs Compose.

Live projects are stored at `/etc/compose-stacks/<stack>` and use the stable
Compose project name `<stack>`. Publication is not performed over the live
directory; staging is validated first and then moved into place.

A live directory may be replaced or removed only when
`.managed-by-github-actions` exists and contains the matching
`STACK_NAME=<stack>` entry. Unmarked directories are intentionally left alone
for manual investigation. The reconciler records failures but continues with
other stacks on the same host, so one failure does not hide the rest of the
report.

Removing a deployment directory causes the next reconciliation to run
`docker compose down --remove-orphans` and remove the marked project directory.
Named volumes and images are intentionally retained.

## Adding or changing a stack

1. Create the root stack directory and base `docker-compose.yaml`.
2. Add the root `.env.template` if shared values are needed.
3. Add one `deployments/<host>/.env.template` per assigned host.
4. Add a host overlay only when the base Compose definition cannot express the
   host-independent configuration.
5. Confirm all external networks are supplied by `docker-networking`.
6. Check bind-mount source types, especially file mounts.
7. Run local validation (below).
8. Push to `main`, or manually dispatch `deploy.yaml` for script-only changes.
9. Inspect the workflow's preflight, platform, and per-host application jobs.

To move a stack between hosts, add the new assignment first, verify the new
host, then remove the old assignment in a subsequent change when a staged
migration is preferable.

## Validation

Preflight is the authoritative repository-wide check:

```bash
ruby .github/scripts/preflight.rb
```

Useful focused checks are:

```bash
ruby -c .github/scripts/preflight.rb
ruby -c .github/scripts/reconcile-platform.rb
ruby -c .github/scripts/reconcile-host.rb
ruby -c .github/scripts/discover-deploy-hosts.rb
git diff --check

docker compose \
  -f compose-stacks/<stack>/docker-compose.yaml \
  -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
  config --quiet
```

The second `-f` is optional. Use representative non-secret values locally;
expected warnings for unset secret variables are acceptable when CI injects
those values through 1Password.

## Failure and recovery process

When a deployment job fails:

1. Inspect the failed application job, not only the aggregate workflow result:

   ```bash
   gh run view --job <job-id> --log-failed
   ```

2. Identify the failing stack/host pair and whether the failure occurred during
   staging, publication, or `compose up`.
3. Do not manually delete an unmarked live directory. Check its marker and
   filesystem contents first.
4. Fix the repository source and validate locally before rerunning.
5. For changes under `.github/scripts`, `.github/workflows`, or other paths not
   covered by the Compose push filter, manually dispatch the workflow:

   ```bash
   gh workflow run deploy.yaml --ref main
   gh run watch <run-id> --exit-status
   ```

The reconciler contains a narrowly scoped migration recovery path for the
known legacy Traefik layout where Docker created nested directories for
`traefik.yml` and `dynamic/`. That path is not a general permission bypass:
all other unmarked live directories remain protected. If a different root-owned
layout appears, investigate its origin and add an explicit, testable migration
rule rather than weakening the marker guard.

## Security rules

- Never print, commit, or upload resolved secrets.
- Do not place runtime `.env` files in Git.
- Keep remote staging and runtime environment files mode `0600`.
- Keep SSH host verification and Tailscale access enabled in CI.
- Do not replace or remove an unmarked live directory automatically.
- Do not make a normal application stack responsible for shared platform
  resources.
