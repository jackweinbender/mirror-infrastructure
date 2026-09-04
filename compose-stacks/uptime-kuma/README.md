# Uptime Kuma

Uptime Kuma is assigned to `docker0-lxc` and exposed through host Traefik at
`https://uptime-kuma.weinbender.io`. The hostname is defined in
`deployments/docker0-lxc/.env.template`.

The stack uses the pinned official `louislam/uptime-kuma:2.5.3` image. Its
application data is stored in the named `uptime_kuma_data` volume. On
`docker0-lxc`, named volumes follow the host-backed Docker data root at
`/srv/guest-volumes/docker`.

The service joins the external `proxy` network supplied by
`docker-networking`; it does not create or manage that network. Add an
unproxied Cloudflare CNAME for `uptime-kuma.weinbender.io` pointing to the
`docker0-lxc` Traefik gateway hostname, following the convention in
[`../traefik/README.md`](../traefik/README.md).

After deployment, complete Uptime Kuma's initial setup through the HTTPS web UI
and create monitors and notifications there. No application credentials are
stored in this repository.

## Validation

From the repository root:

```bash
ruby .github/scripts/preflight.rb
docker compose \
  -f compose-stacks/uptime-kuma/docker-compose.yaml \
  --env-file <(printf 'UPTIME_KUMA_HOSTNAME=uptime-kuma.example.test\n') \
  config --quiet
git diff --check
```

The deployment workflow merges the repository templates and supplies the
runtime environment remotely.

## Operational follow-up

- Add the DNS CNAME described above.
- Complete the initial admin setup.
- Configure monitors and an independent notification path.
- Verify the public URL and at least one monitor after deployment.
- Confirm that the `uptime_kuma_data` volume is covered by host backups.

The repository change only scaffolds the deployment; it does not deploy the
service or configure DNS. Follow the repository-wide recovery and marker rules
in [`../OPERATIONS.md`](../OPERATIONS.md) before taking manual action.

## Upgrade and security

The image tag is pinned rather than using `latest`. Back up the data volume and
review upstream release notes before changing it. Never commit runtime `.env`
files, database files, backups, or credentials.

Sources: [Uptime Kuma](https://github.com/louislam/uptime-kuma),
[Docker image](https://hub.docker.com/r/louislam/uptime-kuma).

Scaffold status: ready for review; not deployed.
