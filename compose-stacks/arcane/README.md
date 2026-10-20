# Arcane

Arcane is assigned to `docker0-lxc` and served through its host-level Traefik
at [`https://arcane.weinbender.io`](https://arcane.weinbender.io). The route
uses the same private-LAN gateway convention as the other services on this
host; it does not publish a raw host port.

The stack pins the official Arcane Manager image to `v2.16.1`. Its application
database and settings persist in the `arcane_data` Docker volume. Arcane's
Compose project and build directories are bind-mounted at the same absolute
paths inside and outside the container, as required for Arcane's Docker-backed
project/build workflows. They live under `/srv/guest-volumes/arcane` on the
persistent guest-volume mount.

## Access and secrets

Arcane mounts `/var/run/docker.sock` read-write so it can manage Docker. This
gives Arcane administrators control equivalent to root on `docker0-lxc`; treat
access to the UI as host-administrator access. The socket is not published over
the network.

Arcane bootstraps the default account `arcane` with password `arcane-admin` and
requires a password change on first login. Log in immediately after deployment
and replace that password. The hostname resolves through the unproxied
Cloudflare CNAME to the host's private LAN address; access is limited to the
LAN/VPN as described in [`../traefik/README.md`](../traefik/README.md).

Create a 1Password item named `arcane` in the `network` vault with these fields:

- `encryption_key` — unique random 32-character value
- `jwt_secret` — unique random secret

The deployment template references these fields through `op://network/arcane/...`.
Do not commit resolved values or a runtime `.env` file.

## DNS and deployment

The Cloudflare component declares an unproxied CNAME from
`arcane.weinbender.io` to `docker0-lxc.weinbender.io`. The gateway A record must
resolve to the host's private LAN IPv4 address. c5e on `docker0-lxc` reconciles
this host's stack assignments through its local Docker daemon; CI validates
configuration only and does not prove that remote state changed.

After deployment, log in and change the default password, confirm Arcane can
reach the local Docker daemon, and verify the `arcane_data` volume plus the
projects/builds directories are covered by backups. Arcane and Komodo can both
control Docker on this host; keep their access and use of those controls
intentional.

## Validation

From the repository root:

```bash
ruby scripts/preflight.rb
tmp_env=$(mktemp)
printf '%s\n' \
  'ARCANE_HOSTNAME=arcane.example.test' \
  'ARCANE_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef' \
  'ARCANE_JWT_SECRET=validation-only-not-a-runtime-secret' > "$tmp_env"
docker compose \
  --env-file "$tmp_env" \
  -f compose-stacks/arcane/docker-compose.yaml \
  config --quiet
rm -f "$tmp_env"
git diff --check
```

Keep real keys out of validation environments and Git. Resolve 1Password
references only as part of an authorized deployment process.

Sources: [Arcane](https://github.com/getarcaneapp/arcane),
[Arcane Docker Compose example](https://github.com/getarcaneapp/arcane/blob/v2.16.1/docker/examples/compose.basic.yaml),
[Arcane environment reference](https://github.com/getarcaneapp/arcane/blob/v2.16.1/.env.example).
