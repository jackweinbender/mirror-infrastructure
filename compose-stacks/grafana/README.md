# Grafana

The stack definition is present, but no `deployments/` assignment currently
targets a host. The repository does not establish whether an instance is
running remotely. The hostname and administrator credentials are defined in
`.env.template`; keep the password in 1Password and do not commit it.

The stack uses the pinned `grafana/grafana:13.0.7` image and persists Grafana
state in the named Docker volume `grafana_data`. When assigned to `docker0-lxc`,
that volume follows the host-backed Docker data root at `/srv/guest-volumes/docker`.

When assigned to `docker0-lxc`, the service uses the external `proxy` network
ensured by c5e; it does not create or manage that network. Add an unproxied
Cloudflare CNAME for `grafana.weinbender.io` pointing to the `docker0-lxc` Traefik
hostname, as described in the [Traefik README](../traefik/README.md).

After deployment, log in with the configured administrator account and
add data sources and dashboards. Provisioning is intentionally left out of this
scaffold so credentials and environment-specific endpoints are not coupled to
the initial service deployment.

To enable the repository assignment, add
`deployments/docker0-lxc/.env.template`; c5e will then reconcile it through
that host's local Docker daemon. The configured `retain` policy means removing
the assignment does not itself stop or remove the live project.
