# Crow CI

Crow CI runs on `docker0-lxc` with one server and one Docker-backed agent. The
server is exposed through the host-level Traefik gateway at
`https://crow.weinbender.io`; the agent protocol port is available only on the
internal Compose network.

The stack is pinned to Crow CI `6.5.0`. Server data, including the default SQLite
database, is stored in the named Docker volume `crow_ci_data`. On `docker0-lxc`,
that volume follows the host-backed Docker data root at
`/srv/guest-volumes/docker`.

The agent mounts the host Docker socket because Crow executes each pipeline step
in a container. Treat pipeline configuration and the agent as equivalent to
host-level access. Its identity configuration is persisted in the named volume
`crow_ci_agent_config`, and the agent uses the stable hostname `docker0-lxc` so
restarts reconnect to the same Crow agent record.

## One-time setup

1. Create a Forgejo OAuth application for Crow CI with this redirect URI:
   `https://crow.weinbender.io/authorize`.
2. Store the OAuth client ID, OAuth client secret, and a randomly generated
   agent secret in the 1Password item paths referenced by
   `deployments/docker0-lxc/.env.template`.
3. Add an unproxied Cloudflare CNAME for `crow.weinbender.io` pointing to the
   `docker0-lxc` Traefik gateway hostname. The gateway A record must already
   point to that host's private LAN address; see the [Traefik README](../traefik/README.md).
4. Deploy the stack, then log in with a Forgejo account and register the agent
   from the Crow CI administration UI if the server requests agent approval.
   If a previous stateless deployment left an offline duplicate, delete that
   old agent record once from the administration UI.

`CROW_OPEN=true` follows the quickstart and permits Forgejo users to register.
Restrict registration with `CROW_ORGS` or change it to `false` after the initial
administrative account is established.

The application assignment is represented by
`deployments/docker0-lxc/.env.template`; remove that assignment to stop the
stack during the next reconciliation.
