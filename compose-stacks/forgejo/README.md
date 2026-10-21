# Forgejo

Forgejo runs on `docker0-lxc` behind the host Traefik. The Cloudflare Tunnel
publishes only `/api/actions/.well-known/openid-configuration` and
`/api/actions/.well-known/keys` at `https://forgejo.weinbender.io`; all other
HTTP paths on that hostname return 404. The hostname is defined in
`.env.template`, but must match the Terraform tunnel ingress and Forgejo's
`ROOT_URL` issuer; update those together if it changes.

Forgejo's Traefik labels add a separate plain-HTTP router for only those two
OIDC paths. The DMZ Traefik uses it over the private LAN; the normal Forgejo
router remains HTTPS-only. Keep the hostname and paths aligned with the
Cloudflare Tunnel ingress.

The stack uses the Forgejo 16.0.2 image and stores repositories and application data
in the named Docker volume `forgejo_data`. On `docker0-lxc`, that volume follows the
host-backed Docker data root at `/srv/guest-volumes/docker`; Compose does not require
or create a per-stack directory on the Proxmox host. Git-over-SSH is available on
host port `2222`; Forgejo advertises that port in its generated clone URLs.

The application assignment is represented by
`deployments/docker0-lxc/.env.template`. c5e on `docker0-lxc` reconciles this
assignment using the host's local Docker daemon. The controller ensures the
external `proxy` network before assigned applications; Traefik must also be
available on this host before Forgejo runs.

Forgejo's webhook delivery honors `FORGEJO__webhook__ALLOWED_HOST_LIST`
(default `external`, which denies private LAN addresses). The Compose
environment extends it with the LAN webhook receivers Forgejo must reach, such
as the `planet-express` stack; add future LAN receivers to that list. A c5e
reconciliation is needed for the updated Compose configuration to take effect.
