# Paseo

Paseo is a self-hosted coding-agent orchestrator: it runs the Paseo daemon and
serves the bundled web UI from the same origin, letting you drive coding agents
(Claude Code, Codex, OpenCode, Pi, etc.) from a browser client. The stack
definition currently has no `deployments/` assignment. The repository does not
establish whether an instance is running remotely.

## Stack

This stack is a **consumer** of the application image owned by the separate
[`labs/paseo`](https://forgejo.weinbender.io/labs/paseo) repository — the image
source (Dockerfile and its build/publish CI) does not live in this repo. That
repo extends the pinned `ghcr.io/getpaseo/paseo:0.9.1` base with the coding-agent
CLIs (Pi by default) and publishes
`forgejo.weinbender.io/labs/paseo:<tag>` to the Forgejo Container Registry. This
compose pins that immutable tag:

```yaml
image: forgejo.weinbender.io/labs/paseo:0.9.1
```

When assigned to a host, its local c5e controller reconciles it through that
host's Docker daemon. The registry is anonymously pullable, so no registry
credentials are needed.

Persistent state and agent credentials are stored in the named `paseo_home`
volume (`/home/paseo` inside the container); `paseo_workspace` (`/workspace`) is
the code mount that launched agents read and write. When assigned to
`docker0-lxc`, named volumes follow its host-backed Docker data root at
`/srv/guest-volumes/docker`.

The image runs the daemon and serves the bundled web UI, listening on `6767`
inside the container. Agent binaries (Pi, and any others added to the
`Dockerfile`) are baked into the image; provider authentication is completed
after deployment either through the web UI or `docker exec -it --user paseo
paseo <agent> login`. See [Paseo · Docker](https://paseo.sh/docs/docker) and
[Paseo · Supported providers](https://paseo.sh/docs/supported-providers).

When assigned, the service joins the external `proxy` network ensured locally
by c5e; it does not create or manage that network. Traefik routes
`https://paseo.weinbender.io` to the container and terminates TLS with
Let's Encrypt. `PASEO_HOSTNAMES` is set to the public hostname so the daemon's
DNS-rebinding protection accepts requests for it.

## Secrets

`PASEO_PASSWORD` is referenced from 1Password as
`op://network/paseo/password`. Create that item before enabling the assignment;
keep the reference unresolved in the template and never commit the resolved
secret or a runtime `.env` file. The Host header is preserved and
`X-Forwarded-Proto` passed by Traefik for WebSocket and `wss://` auto-connect.

## Validation

From the repository root:

```bash
ruby scripts/preflight.rb
tmp_env=$(mktemp)
printf '%s\n' \
  'PASEO_HOSTNAME=paseo.example.test' \
  'PASEO_PASSWORD=validation-only' > "$tmp_env"
docker compose \
  --env-file "$tmp_env" \
  -f compose-stacks/paseo/docker-compose.yaml \
  config --quiet
rm -f "$tmp_env"
git diff --check
```

CI validates repository configuration only. When assigned, c5e on that host
reconciles the stack through its local Docker daemon. Validation does not prove
that remote state changed. Resolve the 1Password-backed password only through
the configured secret process.

## Operational follow-up

- Create the `network/paseo/password` 1Password item referenced above.
- Add an unproxied Cloudflare CNAME for `paseo.weinbender.io` pointing to the
  `docker0-lxc` Traefik gateway hostname. This record is managed in Terraform at
  [`terraform/cloudflare/dns.tf`](../../terraform/cloudflare/dns.tf), following
  the same convention as `ntfy`, `crow`, `uptime-kuma`, and `grafana`.
- Publish the pinned image tag once from the separate
  [`labs/paseo`](https://forgejo.weinbender.io/labs/paseo) repo (its Crow pipeline)
  before updating the Compose tag. Publishing an image does not itself reconcile
  the host assignment.
- Authenticate at least one provider after deployment, either from the web UI
  or `docker exec -it --user paseo paseo <agent> login`; credentials persist in
  `paseo_home`.
- Verify the public URL and a direct daemon connection after deployment.
- Confirm the `paseo_home` and `paseo_workspace` volumes are covered by host
  backups.

This repository change does not create the 1Password item or configure DNS.
The c5e controller is host-local; repository validation alone does not prove
that remote state changed. See [`../OPERATIONS.md`](../OPERATIONS.md) for
ownership and remote-state safety before taking manual action.

## Upgrade and security

The pinned image tag (and the paseo base version it contains) is owned by the
[`labs/paseo`](https://forgejo.weinbender.io/labs/paseo) repo. To upgrade, bump the
version there, republish, then update the pinned `image:` tag in
`docker-compose.yaml` to match. If only the agent CLIs change, publish a new
image tag as well and update the Compose tag; rebuilding an unchanged tag does
not itself alter the c5e assignment. Back up the `paseo_home` volume and review
upstream release notes before changing it. `PASEO_PASSWORD` must be set for any
network-reachable deployment, and traffic uses TLS at the Traefik edge.
Never commit runtime `.env` files or resolved credentials.

Sources: [Paseo](https://paseo.sh), [Paseo · Docker](https://paseo.sh/docs/docker),
[Docker image](https://github.com/getpaseo/paseo/pkgs/container/paseo).

Scaffold status: ready for review; not deployed.