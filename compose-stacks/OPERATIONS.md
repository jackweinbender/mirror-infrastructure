# Compose stack operations

This runbook describes the repository's Compose layout, validation, and
reconciliation safeguards. Compose deployment workflows have been removed;
the remaining CI pipeline validates configuration but does not deploy stacks.

## Architecture

Compose stacks have two ownership classes:

- **Platform stack**: `docker-networking` owns the external `proxy` network,
  which dependent application stacks require.
- **Application stacks**: every other stack is assigned through deployment
  directories. Traefik is an application stack, not part of the platform stack.
  Assignments may target `deploy` or `c5e_reconciler` hosts. c5e reconciles
  assignments on its own controller host.

There are no Compose deployment workflows in `.crow/`. Compose validation
checks inventory, stack names, dotenv templates, assignments, overlays, and
Compose configuration; it does not connect to hosts or deploy. Deploy-host
assignments remain configuration, but pushes and assignment changes do not
reconcile them automatically.

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
assignment. The host must have either `deploy` or `c5e_reconciler` in
`host_roles`. Preflight validates application assignments on both host types;
c5e reconciles assignments on its own controller host.

There is no `deployments/ALL/` convention. The platform stack is intended for
every Docker host with `host_roles: deploy`; application stacks must enumerate
their actual host assignments. c5e-managed hosts ensure the shared `proxy`
network directly before dependent applications.

### Compose overlays

When deployment tooling uses an optional `deployments/<host>/docker-compose.yaml`,
it is copied to the staged project as `docker-compose.override.yaml`, so the
same Compose commands work for every host. An overlay does not assign a stack.

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

Deployment tooling merges the templates, resolves 1Password references, and
writes the resolved `.env` to private remote staging. Do not create or commit
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

When a deployment tool reconciles an application assignment on a `deploy` host,
the host reconciler:

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

Removing an assignment on a `deploy` host does not automatically stop or remove
its live project now that the Compose deployment workflows are gone. Assignments
on a `c5e_reconciler` host remain subject to that controller's configured
removal policy.

## Adding or changing a stack

1. Create the root stack directory and base `docker-compose.yaml`.
2. Add the root `.env.template` if shared values are needed.
3. Add one `deployments/<host>/.env.template` per assigned host.
4. Add a host overlay only when the base Compose definition cannot express the
   host-independent configuration.
5. Ensure external `proxy` is supplied by the platform stack on deploy hosts or
   c5e's direct ensure on controller hosts; provision other external networks
   separately.
6. Check bind-mount source types, especially file mounts.
7. Run local validation (below).
8. Run the repository's preflight and focused Compose validation. The Compose
   validation pipeline does not deploy, and this repository has no Compose
   deployment workflow; a push is not evidence that a stack was reconciled.
9. Use the separately authorized operational process for any required host
   deployment. c5e continues to reconcile assignments on its own controller.

To move a stack between hosts, add the new assignment first, verify the new
host, then remove the old assignment in a subsequent change when a staged
migration is preferable.

## Validation

Preflight is the authoritative repository-wide check:

```bash
ruby scripts/preflight.rb
```

Useful focused checks are:

```bash
ruby -c scripts/preflight.rb
ruby -c scripts/reconcile-platform.rb
ruby -c scripts/reconcile-host.rb
ruby -c scripts/discover-deploy-hosts.rb
git diff --check

docker compose \
  -f compose-stacks/<stack>/docker-compose.yaml \
  -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
  config --quiet
```

The second `-f` is optional. Use representative non-secret values locally.

## Failure and recovery process

When a separately authorized deployment process fails:

1. Inspect the failing stack/host pair and determine whether the failure
   occurred during staging, publication, or `compose up`.
2. Do not manually delete an unmarked live directory. Check its marker and
   filesystem contents first.
3. Fix the repository source and validate locally before retrying the approved
   deployment process.

The repository has no Compose deployment workflow to dispatch or inspect.
Preflight and Compose validation do not prove that remote state changed.

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
- Keep SSH host verification and Tailscale access enabled in authorized
  deployment tooling.
- Do not replace or remove an unmarked live directory automatically.
- Do not make a normal application stack responsible for shared platform
  resources.
