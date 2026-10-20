# Komodo

Komodo Core and its Periphery agent run together on `docker0-lxc`. Core is
exposed through the host Traefik gateway at
[`https://komodo.weinbender.io`](https://komodo.weinbender.io); MongoDB and
Periphery are not published on host ports. The stack pins Komodo `2.3.3` and
MongoDB `8.0.34`.

MongoDB data, generated Core/Periphery keys, and Core backups use named Docker
volumes under the LXC's persistent Docker data root. Periphery's working root
is `/srv/guest-volumes/komodo`, on the persistent guest-volume mount, so stacks
and repositories it manages survive container replacement.

## Access and secrets

Periphery mounts `/var/run/docker.sock`, which grants control equivalent to
root on `docker0-lxc`. This is required for Komodo to manage that host's Docker
resources. Periphery terminal and container-terminal APIs are disabled; the
Docker socket still provides broad host control to Komodo administrators. The
agent connects only over the private Compose network and does not publish its
port.

Deployment secrets are stored in a 1Password item named `komodo` in the
`network` vault, with these fields:

- `database_password` — MongoDB root password
- `admin_password` — initial `jackweinbender` Komodo password
- `jwt_secret` — persistent JWT signing secret
- `webhook_secret` — webhook authentication secret

The deployment template references these values with `op://network/komodo/...`.
Local authentication is enabled and new-user registration is disabled.

## DNS and deployment

Terraform declares an unproxied Cloudflare CNAME from
`komodo.weinbender.io` to `docker0-lxc.weinbender.io`; the gateway A record must
already resolve to the host's private LAN address. Apply the Cloudflare
component before relying on the public hostname. c5e on `docker0-lxc` reconciles
this host's stack assignments through its local Docker daemon; CI validation
does not deploy or prove that remote state changed.

After deployment, log in with the initial admin credentials from 1Password and
confirm the `docker0-lxc` Periphery server is online. Confirm the MongoDB,
Komodo keys, backup, and Periphery working-root data are included in backups.

## Validation

From the repository root:

```bash
ruby scripts/preflight.rb
docker compose \
  --env-file compose-stacks/komodo/deployments/docker0-lxc/.env.template \
  -f compose-stacks/komodo/docker-compose.yaml \
  config --quiet
git diff --check
```

Never commit runtime `.env` files or resolved credentials. Resolve secrets only
as part of an authorized deployment process.

Sources: [Komodo](https://komo.do/),
[Komodo Compose deployment](https://github.com/moghtech/komodo/blob/v2.3.3/compose/mongo.compose.yaml),
[Komodo Compose variables](https://github.com/moghtech/komodo/blob/v2.3.3/compose/compose.env).

Scaffold status: ready for deployment; not deployed.
