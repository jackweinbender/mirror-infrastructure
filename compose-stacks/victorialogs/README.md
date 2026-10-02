# VictoriaLogs

[VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) is a single-node
log database that accepts Docker/`syslog`/JSON log ingestion on port `9428` and
serves LogsQL read queries and a built-in web UI from the same port. This stack
is assigned to the `lxc-docker-core0` deploy host and is a pure consumer of the
upstream `docker.io/victoriametrics/victoria-logs` image pinned to an immutable
tag:

```yaml
image: docker.io/victoriametrics/victoria-logs:v1.53.0
```

The reconciler pulls the pinned tag on each deployment (`--pull always`), so no
registry credentials are needed here.

## Stack

- `victorialogs` container listens on `9428` and writes its log data under
  `/vlogs`, persisted in the named `vlogs_data` volume. On `lxc-docker-core0`
  named volumes are host-backed below the Docker data root.
- Retention is set to **30 days** (`-retentionPeriod=30d`). Tune the retention
  and consider `-retention.maxDiskSpaceUsageBytes` if this host's storage budget
  needs a hard cap.
- The service joins the external `proxy` network supplied by
  `docker-networking`; it does not create or manage that network. Traefik routes
  `https://victorialogs.weinbender.io` to the container and terminates TLS with
  Let's Encrypt.
- The image (v1.52+) is **distroless**: it ships no shell, `curl`, or `wget`, so
  a container-exec `CMD-SHELL` healthcheck cannot run. Health is instead tracked
  at the Traefik edge; this is documented rather than adding a healthcheck that
  would never succeed.

The web UI is served at `https://victorialogs.weinbender.io/select/vmui/`, and
the ingestion endpoint for a vector/`vlagent`/syslog shipper is
`/insert/jsonline` etc. on the same origin.

## Validation

From the repository root:

```bash
ruby .github/scripts/preflight.rb
tmp_env=$(mktemp)
printf '%s\n' \
  'VICTORIALOGS_HOSTNAME=victorialogs.example.test' > "$tmp_env"
docker compose \
  --env-file "$tmp_env" \
  -f compose-stacks/victorialogs/docker-compose.yaml \
  config --quiet
rm -f "$tmp_env"
git diff --check
```

The deployment workflow merges the repository templates and supplies the runtime
environment remotely; no secrets are needed for this stack.

## Operational follow-up

The repository change only scaffolds the deployment. Before the web UI is
reachable over the public hostname, complete the following (each is a separate
prerequisite, none is created by this change):

- **Gateway A record:** `lxc-docker-core0.weinbender.io` → the host's LAN IPv4
  address (matches the `docker0-lxc`/`traefik-lxc` convention). This is a
  Proxmox/LXC provisioning follow-up, not an Ansible or Compose task.
- **Traefik on this host:** this host joins the `proxy` network only if Traefik
  is assigned to run here. Confirm `compose-stacks/traefik/deployments/lxc-docker-core0/`
  exists (or add it) so HTTP/HTTPS ingress terminates on this host.
- **Service CNAME:** an unproxied Cloudflare CNAME for `victorialogs.weinbender.io`
  → `lxc-docker-core0.weinbender.io`, managed in
  `terraform/cloudflare/dns.tf` following the `ntfy`/`crow`/`grafana` convention.
- **Backups:** confirm the `vlogs_data` volume is covered by host backups.
- **Shipping logs:** point a log shipper (the `vector` host agent, `vlagent`, or
  syslog) at the `/insert/...` endpoint when log collection to this store is
  desired; that wiring is out of scope for this scaffold.

## Upgrade and security

To upgrade, bump the pinned `image:` tag to the next upstream release and re-run
the deployment. VictoriaLogs has no built-in authentication; it must stay
behind the Traefik edge (or another auth boundary) and is not exposed on a raw
host port. Never commit runtime `.env` files or credentials.

Sources: [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/),
[Docker image](https://hub.docker.com/r/victoriametrics/victoria-logs).

Scaffold status: ready for review; not deployed.
