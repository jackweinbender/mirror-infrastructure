# Planet Express

Planet Express is the Forgejo webhook receiver from the
[`labs/planet-express`](https://forgejo.weinbender.io/labs/planet-express) repository.
This stack consumes its image; image build and publish CI live in that
repository. The stack is assigned to `docker0-lxc` and exposed through host
Traefik at `https://planet-express.weinbender.io`.

## Stack

The Compose definition pins an immutable full-SHA image tag:

```yaml
image: forgejo.weinbender.io/labs/planet-express:f66c5c668bf319d6dd3c965976795e3cf734292a
```

To upgrade, merge the desired change in `labs/planet-express`, let CrowCI
publish its new SHA tag, then update the pinned tag here. c5e on `docker0-lxc`
reconciles this host's assignment through its local Docker daemon. The registry
is anonymously pullable and requires no per-host Docker login.

The receiver listens on port `8080`. Its SQLite database is stored at
`/data/events.db` in the named `planet_express_data` volume. On `docker0-lxc`,
Docker volumes live under the host-backed data root at
`/srv/guest-volumes/docker`; confirm this volume is covered by host backups.

When upgrading from the old root-running Go container to the Chainguard Node
image, change ownership of the existing named-volume data once before
deploying the non-root image:

```bash
sudo chown -R 65532:65532 /srv/guest-volumes/docker/volumes/planet_express_data/_data
```

Run that one-time migration only for the existing `planet_express_data` volume
on `docker0-lxc`; otherwise the new container will not be able to write its
SQLite database.

The service joins the external `proxy` network ensured by c5e on `docker0-lxc`;
it does not create or manage that network. Traefik routes the configured
hostname and terminates TLS with Let's Encrypt.

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

CI validates repository configuration only; c5e on `docker0-lxc` reconciles
this host's assignment through its local Docker daemon. Validation does not
prove remote state changed. Resolve the 1Password-backed secret only through the
configured secret process.

## Operational follow-up

- Create the `network/planet-express/webhook-secret` 1Password item.
- Apply Terraform to publish the Cloudflare CNAME; the record is included in
  this change, but applying it is manual.
- The local c5e controller on `docker0-lxc` reconciles this host's assignment;
  CI validation does not prove that the host has applied the Compose change.
- Register the Forgejo webhook with the matching secret.
- Verify `https://planet-express.weinbender.io/healthz` after deployment.
- Confirm `planet_express_data` is covered by backups.

This repository change does not create the 1Password item, apply DNS, or
register the Forgejo webhook. The c5e controller is host-local; repository
validation alone does not prove that remote state changed. See
[`../OPERATIONS.md`](../OPERATIONS.md) for ownership and remote-state safety
before manual recovery.

Scaffold status: ready for review; not deployed.
