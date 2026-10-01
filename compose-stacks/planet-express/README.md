# Planet Express

Planet Express is the Forgejo webhook receiver from the
[`labs/planet-express`](https://git.weinbender.io/labs/planet-express) repository.
This stack consumes its image; image build and publish CI live in that
repository. The stack is assigned to `docker0-lxc` and exposed through host
Traefik at `https://planet-express.weinbender.io`.

## Stack

The Compose definition pins an immutable full-SHA image tag:

```yaml
image: git.weinbender.io/labs/planet-express:f66c5c668bf319d6dd3c965976795e3cf734292a
```

To upgrade, merge the desired change in `labs/planet-express`, let CrowCI
publish its new SHA tag, then update the pinned tag here. The deployment
reconciler uses `--pull always`, so it fetches the tag on reconciliation. The
registry is anonymously pullable and requires no per-host Docker login.

The receiver listens on port `8080`. Its SQLite database is stored at
`/data/events.db` in the named `planet_express_data` volume. On `docker0-lxc`,
Docker volumes live under the host-backed data root at
`/srv/guest-volumes/docker`; confirm this volume is covered by host backups.

The service joins the external `proxy` network supplied by `docker-networking`.
Traefik routes the configured hostname and terminates TLS with Let's Encrypt.

## Secrets

`WEBHOOK_SECRET` comes from 1Password as
`op://network/planet-express/webhook-secret`. Create the item before deploying;
the same value must be configured on the Forgejo webhook.

## Webhook registration

In Forgejo, add a webhook for the desired repository or repositories with target
`https://planet-express.weinbender.io/webhook/forgejo`, choose the desired event
types, and set the secret to the 1Password value. For local testing, use
`labs/planet-express/scripts/send-event.sh` with `BASE` and `WEBHOOK_SECRET`
environment variables.

## Validation

From the repository root:

```bash
ruby scripts/preflight.rb
tmp_env=$(mktemp)
printf '%s\n' \
  'PLANET_EXPRESS_HOSTNAME=planet-express.example.test' \
  'WEBHOOK_SECRET=validation-only' > "$tmp_env"
docker compose --env-file "$tmp_env" \
  -f compose-stacks/planet-express/docker-compose.yaml config --quiet
rm -f "$tmp_env"
git diff --check
```

The deployment workflow merges the repository templates and supplies the
runtime environment, including the 1Password-resolved secret, remotely.

## Operational follow-up

- Create the `network/planet-express/webhook-secret` 1Password item.
- Apply Terraform to publish the Cloudflare CNAME; the record is included in
  this change, but applying it is manual.
- Dispatch the Crow `deploy` workflow.
- Register the Forgejo webhook with the matching secret.
- Verify `https://planet-express.weinbender.io/healthz` after deployment.
- Confirm `planet_express_data` is covered by backups.

The repository change only scaffolds this deployment; it does not create the
1Password item, apply DNS, deploy the service, or register the webhook.
Follow the repository-wide recovery and marker rules in
[`../OPERATIONS.md`](../OPERATIONS.md) before manual recovery.

Scaffold status: ready for review; not deployed.
