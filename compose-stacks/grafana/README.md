# Grafana

Grafana runs on `docker0-lxc` and is exposed through the host Traefik at
`https://grafana.weinbender.io`. The hostname and administrator credentials are
defined in `.env.template`; the password is resolved from 1Password during the
GitHub Actions deployment and is never committed to the repository.

The stack uses the pinned `grafana/grafana:13.0.7` image and persists Grafana
state in the named Docker volume `grafana_data`. On `docker0-lxc`, that volume
follows the host-backed Docker data root at `/srv/guest-volumes/docker`.

The service uses the external `proxy` network provided by
`docker-networking`. Add an unproxied Cloudflare CNAME for
`grafana.weinbender.io` pointing to the `docker0-lxc` Traefik gateway hostname,
as described in the [Traefik README](../traefik/README.md).

After the first deployment, log in with the configured administrator account and
add data sources and dashboards. Provisioning is intentionally left out of this
scaffold so credentials and environment-specific endpoints are not coupled to
the initial service deployment.

The application assignment is represented by
`deployments/docker0-lxc/.env.template`; remove that assignment to stop the
stack during the next reconciliation.
