---
name: compose-deployments
description: Maintain and validate this repository's Docker Compose stacks, host assignments, overlays, and reconciliation safeguards. Compose deployment workflows are absent; c5e independently reconciles its controller-host assignments.
---

# Compose deployments

Use this skill for any change involving `compose-stacks/`, Compose deployment
workflow behavior, stack assignments, host overlays, or deployment failures.
Read [`../../../compose-stacks/OPERATIONS.md`](../../../compose-stacks/OPERATIONS.md)
for the full repository runbook before making non-trivial changes.

## Repository model

- `compose-stacks/docker-networking/` is the platform stack. It owns the
  external `proxy` network.
- Every other Compose stack is an application stack. Traefik is a normal
  assigned application stack, not part of the platform stack.
- Application assignment hosts must have `deploy` or `c5e_reconciler` in
  `host_roles`. c5e reconciles assignments on its own host independently of CI.
- No Compose deployment workflows are configured; deploy-host assignments are
  not automatically reconciled by CI.
- Never introduce `deployments/ALL/`. Assignment is explicit for application
  stacks; only `docker-networking` has implicit all-deploy-host behavior in the
  retained reconciliation model.

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
short inventory host ID. The host must have `deploy` or `c5e_reconciler`. An
overlay does not assign a stack; deployment tooling copies it to staging as
`docker-compose.override.yaml`.

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

## Validation for changes

1. Inspect the relevant stack README and `compose-stacks/OPERATIONS.md`.
2. Confirm the target host exists in `ansible/inventory.yaml` and has `deploy`
   or `c5e_reconciler` in `host_roles`.
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

   Omit the second file when no overlay exists. Compose validation checks
   configuration only. No CI deployment workflow exists; pushes and assignment
   changes do not deploy or remove live projects on `deploy` hosts.

## Deployment safety

The retained reconciler scripts stage privately, resolve and inject `.env`,
validate Compose, then publish to `/etc/compose-stacks/<stack>` using the stable
Compose project name `<stack>`. They may replace or remove only a live directory
containing a regular `.managed-by-github-actions` marker with the matching
`STACK_NAME=<stack>` entry. No CI workflow invokes these scripts.

Do not weaken this marker guard or manually remove an unmarked live directory.
If a migration creates a known stale layout, identify it by a narrow, explicit
filesystem predicate and add recovery only for that layout. Preserve normal
failure behavior for all unrelated unmarked directories.

The intended deployment order is platform first, application stacks second. A
failed stack is reported after other stacks on that host are attempted; a
connectivity failure or failed teardown must not trigger destructive cleanup.

Removing an assignment from a `deploy` host does not automatically stop or
remove its live project now that the Compose deployment workflows are absent.
Assignments on `c5e_reconciler` hosts are handled by c5e's configured removal
policy.

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
