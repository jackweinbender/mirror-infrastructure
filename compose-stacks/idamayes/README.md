# idamayes

The `idamayes` web service uses the requested image
`forgejo.weinbender.io/idamayes/idamayes.com:main` and is assigned to
`docker0-lxc`. Traefik exposes it over HTTPS at
[`https://idamayes.weinbender.io`](https://idamayes.weinbender.io), forwarding to
container port `8080` over the platform-owned external `proxy` network. No host
port is published.

The `main` image tag is intentionally used as requested; it is mutable, and the
reconciler pulls it on every deployment. The target host must be able to pull
this image; deployment workflows do not exist in this repository.

No healthcheck, environment settings, or persistent data requirements were
provided for the image, so this stack does not invent them. Add the appropriate
configuration if the service requires it.

## DNS and deployment

The Cloudflare Terraform component declares
`idamayes.weinbender.io CNAME docker0-lxc.weinbender.io` as an unproxied record.
The DNS change is not live until the Cloudflare Terraform component is applied.
There is no Crow deployment workflow. Apply the Cloudflare component as
appropriate and use a separately authorized deployment process. Verify the
HTTPS route after deployment.

## Validation

From the infrastructure repository root:

```bash
ruby scripts/preflight.rb
docker compose \
  --env-file compose-stacks/idamayes/deployments/docker0-lxc/.env.template \
  -f compose-stacks/idamayes/docker-compose.yaml config --quiet
git diff --check
```
