---
name: compose-deployments
description: Maintain and deploy this repository's Docker Compose stacks using deployment folders, host overlays, docker-networking platform reconciliation, 1Password-backed env templates, and guarded GitHub Actions publication. Use when adding, changing, debugging, or documenting compose-stacks deployments.
---

# Compose deployments

Use this skill for any change involving `compose-stacks/`, Compose deployment
workflow behavior, stack assignments, host overlays, or deployment failures.
Read [`../../../compose-stacks/OPERATIONS.md`](../../../compose-stacks/OPERATIONS.md)
for the full repository runbook before making non-trivial changes.

## Repository model

- `compose-stacks/docker-networking/` is the platform stack. It owns the
  external `proxy` network and is reconciled on every host discovered from
  `ansible/inventory.yaml` with `host_roles: deploy`.
- Every other Compose stack is an application stack. Traefik is a normal
  assigned application stack, not part of the platform stack.
- Never introduce `deployments/ALL/`. Assignment is explicit for application
  stacks; only `docker-networking` has implicit all-host behavior.

Use this shape for application stacks:

```text
compose-stacks/<stack>/
  docker-compose.yaml
  .env.template                 # optional shared values
  deployments/
    <host>/
      .env.template             # assignment and host-specific values
      docker-compose.yaml       # optional host overlay
```

The presence of `deployments/<host>/.env.template` assigns the stack to that
short inventory host ID. An overlay does not assign a stack; it is copied to
the remote staging directory as `docker-compose.override.yaml`.

## Environment and secrets

- Use `.env.template`, not `.env.template.shared` or another alternate
  convention.
- Root `.env.template` holds shared values and is optional.
- Host `.env.template` holds assignment-specific values and overrides shared
  values.
- Keep `op://...` references in templates; never commit resolved values or
  runtime `.env` files.
- Do not print secrets, pass them as command-line arguments, or store them in
  runner artifacts.

## Compose and filesystem rules

- Keep common configuration in the root Compose file; use overlays only for
  host-specific mounts, ports, resources, or service settings.
- Treat every bind source as a type-sensitive path. A source intended to be a
  file must already exist as a regular file in the repository. Docker creates a
  missing bind source as a root-owned directory, which can break the service
  and prevent the `deploy` user from cleaning it up.
- Shared `proxy` is external and provided by `docker-networking`; application
  stacks must not create or remove it.
- Persistent writable application data belongs in an intentional volume or
  data directory, not in configuration files copied with the stack.

## Required workflow for changes

1. Inspect the relevant stack README and `compose-stacks/OPERATIONS.md`.
2. Confirm the target host exists in `ansible/inventory.yaml` and has
   `host_roles: deploy`.
3. Update the base Compose file, root env template, host assignment template,
   and/or host overlay as appropriate.
4. Verify every bind source is the expected regular-file or directory type.
5. Run:

   ```bash
   ruby scripts/preflight.rb
   ruby -c scripts/preflight.rb
   ruby -c scripts/reconcile-platform.rb
   ruby -c scripts/reconcile-host.rb
   ruby -c scripts/discover-deploy-hosts.rb
   git diff --check
   ```

6. Run focused Compose validation with representative non-secret values:

   ```bash
   docker compose \
     -f compose-stacks/<stack>/docker-compose.yaml \
     -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
     config --quiet
   ```

   Omit the second file when no overlay exists. Expected warnings for unset
   secret variables are acceptable locally when CI injects them through
   1Password.
7. For deployment workflow or script-only changes, manually dispatch the
   workflow because the push path filter may not include those files:

   ```bash
   gh workflow run deploy.yaml --ref main
   gh run watch <run-id> --exit-status
   ```

8. Inspect failed matrix jobs individually with:

   ```bash
   gh run view --job <job-id> --log-failed
   ```

## Deployment safety

The reconciler stages privately, resolves and injects `.env`, validates Compose,
then publishes to `/etc/compose-stacks/<stack>` using the stable Compose project
name `<stack>`. It may replace or remove only a live directory containing a
regular `.managed-by-github-actions` marker with the matching
`STACK_NAME=<stack>` entry.

Do not weaken this marker guard or manually remove an unmarked live directory.
If a migration creates a known stale layout, identify it by a narrow, explicit
filesystem predicate and add recovery only for that layout. Preserve normal
failure behavior for all unrelated unmarked directories.

The deployment order is platform first, application stacks second. A failed
stack is reported after other stacks on that host are attempted; a connectivity
failure or failed teardown must not trigger destructive cleanup.

When changing a stack assignment, remember that removing the assignment causes
workflow reconciliation to run `docker compose down --remove-orphans` and
remove the marked project directory, while retaining named volumes and images.

## Ingress and DNS

When adding a service, choose the ingress path before creating DNS:

- A Cloudflare Tunnel service points its CNAME directly at the tunnel target.
- A service behind a LAN Traefik gateway requires an unproxied A record for
  `<gateway>.weinbender.io` pointing to the gateway's private LAN IPv4 address,
  plus an unproxied CNAME from `<service>.weinbender.io` to the gateway hostname.
- Create the gateway A record as a provisioning follow-up once the gateway LXC
  address is known; this is not an Ansible task. Add the service CNAME when the
  service is assigned to the gateway.
- The DNS hostname must exactly match the Traefik `Host(...)` rule. Most records
  are dashboard-managed; if Terraform owns them, keep them in
  `terraform/cloudflare/dns.tf` with `proxied = false` and `ttl = 1`.

Do not point a LAN-backed service at the tunnel target or assume `dns.tf` contains
all records in the zone. See the relevant stack README and
`terraform/cloudflare/README.md` for the authoritative examples.

## Documentation

Keep the relevant stack README and
[`../../../compose-stacks/OPERATIONS.md`](../../../compose-stacks/OPERATIONS.md)
consistent with behavior changes. If the deployment safety model changes, update the relevant repository
operations documentation as well.
