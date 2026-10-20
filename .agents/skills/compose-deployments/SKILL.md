---
name: compose-deployments
description: Maintain and validate Docker Compose stacks and host-local c5e assignments. Each deployment host runs its own controller against its local Docker socket.
---

# Compose deployments

Use this skill for any change involving `compose-stacks/`, Compose deployment
workflow behavior, stack assignments, host overlays, or deployment failures.
Read [`../../../compose-stacks/OPERATIONS.md`](../../../compose-stacks/OPERATIONS.md)
for the full repository runbook before making non-trivial changes.

## Repository model

- Every Compose stack is an application stack. c5e provides the external `proxy`
  network on each deployment host; there is no `docker-networking` platform stack.
- Application assignments belong only to `deployment_hosts`, the deployment
  subset of `stack_hosts`. The presence of `deployments/<host>/.env.template`
  assigns the stack to that exact `inventory_hostname_short`. Each deployment
  host owns its controller, which reconciles only that host's assignments
  through its local Docker socket.
- CI validates configuration but does not deploy stacks. Assignment changes
  are consumed by the host-local c5e controller.
- Never introduce `deployments/ALL/`; assignments are explicit per hostname.

Use this shape for application stacks:

```text
compose-stacks/<stack>/
  docker-compose.yaml
  .env.template                 # optional shared values
  deployments/
    <inventory_hostname_short>/
      .env.template             # assignment and host-specific values
      docker-compose.yaml       # optional host overlay
```

The presence of
`deployments/<inventory_hostname_short>/.env.template` assigns the stack to the
host whose exact `inventory_hostname_short` matches that directory. That host
must belong to `deployment_hosts`, the deployment-capable subset of
`stack_hosts`. An overlay does not assign a stack; the host-local c5e controller
uses it as the Compose override.

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
  and impede recovery by the host-local controller.
- Shared `proxy` is external and provided by c5e; application stacks must not
  create or remove it.
- Persistent writable application data belongs in an intentional volume or
  data directory, not in configuration files copied with the stack.

## Validation for changes

1. Inspect the relevant stack README and `compose-stacks/OPERATIONS.md`.
2. Confirm the target hostname exists in `ansible/inventory.yaml` and belongs to
   `deployment_hosts`.
3. Update the base Compose file, root env template, host assignment template,
   and/or host overlay as appropriate.
4. Verify every bind source is the expected regular-file or directory type.
5. Run:

   ```bash
   ruby scripts/preflight.rb
   ruby -c scripts/preflight.rb
   git diff --check
   ```

6. Run focused Compose validation with representative non-secret values:

   ```bash
   docker compose \
     -f compose-stacks/<stack>/docker-compose.yaml \
     -f compose-stacks/<stack>/deployments/<host>/docker-compose.yaml \
     config --quiet
   ```

   Compose validation checks configuration only. The c5e controller on a
   deployment host reconciles only that host's assignments using its local
   Docker socket.

## Deployment safety

Each deployment host has exactly one c5e controller, which reconciles that
host's assignments through its local Docker daemon. c5e ensures the local
`proxy` network before assigned applications. Initialize each controller on
its own host with that host's credentials, inspecting that host's local network
and daemon IDs. Never reuse a shared credential/network-ID pair across hosts;
initialization is per-host, not fleet-wide.
c5e does not automatically adopt existing Docker resources by project name.
Foreign or mixed ownership blocks Up/Down; historical automation markers do not
grant adoption permission. Its `retain` removal policy leaves removed
assignments and orphaned projects in place. Never manually remove remote
Compose state without first establishing that it is safe; preserve unrelated
live projects and data. Do not imply an operational rollout or live-stack
handoff as part of an assignment change.

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
