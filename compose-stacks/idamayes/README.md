# idamayes

The `idamayes` web service uses the requested image
`forgejo.weinbender.io/idamayes/idamayes.com:main` and is assigned to
`docker0-lxc`. Traefik exposes it over HTTPS at
[`https://idamayes.weinbender.io`](https://idamayes.weinbender.io), forwarding to
container port `8080` over the external `proxy` network ensured by c5e on
`docker0-lxc`. No host port is published.

The `main` image tag is intentionally used as requested; it is mutable. The
target host must be able to pull the image. c5e on `docker0-lxc` reconciles this
host's assignment through its local Docker daemon; CI validates configuration
but does not deploy or prove that remote state changed.

No healthcheck, environment settings, or persistent data requirements were
provided for the image, so this stack does not invent them. Add the appropriate
configuration if the service requires it.

## DNS and deployment

The Cloudflare Terraform component declares
`idamayes.weinbender.io CNAME docker0-lxc.weinbender.io` as an unproxied record.
The DNS change is not live until the Cloudflare Terraform component is applied.
c5e on `docker0-lxc` reconciles the stack assignment with its local Docker
daemon. Verify the HTTPS route after the DNS and host-local service are ready;
repository validation alone does not prove that remote state changed.

## Validation

From the infrastructure repository root:

```bash
ruby scripts/preflight.rb
docker compose \
  --env-file compose-stacks/idamayes/deployments/docker0-lxc/.env.template \
  -f compose-stacks/idamayes/docker-compose.yaml config --quiet
git diff --check
```
