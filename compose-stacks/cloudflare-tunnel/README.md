# compose-stacks/cloudflare-tunnel

Cloudflare Tunnel stack for public ingress (Zero Trust Access). Traefik is deployed once per Docker host as the normal `compose-stacks/traefik` stack.

## Services

| Service | Image | Purpose |
|---------|-------|---------|
| `cloudflared` | `cloudflare/cloudflared:latest` | Cloudflare Tunnel endpoint for Zero Trust |
| Host Traefik | `traefik:v3.7` | Host-level L7 reverse proxy and auto-TLS (deployed separately) |

## Architecture

```
Internet → Cloudflare Edge
    ├─ Zero Trust Access (Google OAuth + email allowlist, service tokens)
    └─ Cloudflare Tunnel → cloudflared (host) → Traefik (host) → Services
```

- **Cloudflare Tunnel**: Terminates at `cloudflared` on VM. Created by `terraform/cloudflare/` (Plan 001).
- **Traefik**: Deployed by `compose-stacks/traefik`; handles routing, TLS certs (via the `letsencrypt` resolver using DNS-01), and label-based service discovery.
- **Zero Trust Access**: Policies enforced at Cloudflare edge before traffic reaches tunnel.

## Traefik Configuration

Host-level configuration lives in `compose-stacks/traefik/`. This stack joins the external `proxy` network and contributes application containers via Docker labels.


## Cloudflare Tunnel

After `terraform apply` in `terraform/cloudflare/`:
1. Go to Cloudflare Zero Trust → Networks → Tunnels → `weinbender-io` → Configure
2. Copy tunnel token
3. Store in 1Password: `op://network/cloudflare-tunnel-weinbender-io/credential`

## Secrets (`deployments/docker-vm-dmz/.env.template`)

| Variable | 1Password Path | Purpose |
|----------|----------------|---------|
| `CLOUDFLARE_TUNNEL_TOKEN` | `op://network/cloudflare-tunnel-weinbender-io/credential` | Tunnel credential |
| `CF_DNS_API_TOKEN` | `op://network/cloudflare-auth-weinbenderio/credential` | Cloudflare API token (Zone:DNS:Edit) |

The deployment template is kept with the deployment-specific files and injected at deploy via `op inject` — resolved secrets never persist on the runner.

## Deploy

The application assignment is represented by a deployment directory such as `deployments/docker-vm-dmz/`, containing `.env.template`. Add another `deployments/<deploy-host>/.env.template` file to run this stack on another inventory host. A deployment may also include `deployments/<deploy-host>/docker-compose.yaml` for host-specific Compose overrides. Remove the deployment directory to stop it there; the application workflow tears down Compose before deleting its remote files.

Prerequisites:
1. Deploy with `deploy.yaml`; it reconciles `compose-stacks/docker-networking` first so the external `proxy` network exists, then deploys Traefik and application stacks.
2. Apply `terraform/cloudflare/` if using the tunnel.
3. Store the tunnel token in 1Password.

For local validation, merge `.env.template` and a host assignment using a representative token value and run `docker compose config --quiet`. CI resolves `op://` references with `op inject`; the resolved `.env` is never committed or stored on the runner.

## Add a New Service

1. Add the service and its Traefik router to the appropriate stack. For a
   Docker-discovered service, the labels look like:

   ```yaml
     myservice:
       image: myorg/myservice:latest
       networks: [proxy]
       labels:
         - "traefik.enable=true"
         - "traefik.http.routers.myservice.rule=Host(`myservice.weinbender.io`)"
         - "traefik.http.routers.myservice.entrypoints=websecure"
         - "traefik.http.routers.myservice.tls.certresolver=letsencrypt"
   ```

2. Choose the ingress path before adding DNS:
   - **Host Traefik gateway:** the required convention is an `A` record for
     `<gateway>.weinbender.io` pointing to the gateway's LAN IPv4 address,
     plus a `CNAME` from `<service>.weinbender.io` to
     `<gateway>.weinbender.io`; both must be unproxied. Most DNS records are
     currently managed in the Cloudflare dashboard rather than Terraform. If
     managing these records in Terraform, add them to
     `terraform/cloudflare/dns.tf` with `proxied = false`.
   - **Cloudflare Tunnel:** add a CNAME from `<service>.weinbender.io` to the
     tunnel target, as with the existing `uk2026` and `helloworld` records.

3. Ensure the DNS hostname and the Traefik `Host(...)` rule are identical.
4. Deploy and verify the resulting Terraform plan and Traefik route.

For a host-level Traefik gateway, creating only the service CNAME is
insufficient: the gateway's A record must exist first so the CNAME chain ends
at the LAN address of the correct gateway. This two-record convention applies
regardless of whether the records are created in Terraform or manually in the
Cloudflare dashboard.

## Zero Trust Access (from terraform/cloudflare/access.tf)

| Application | Domain | Policy |
|-------------|--------|--------|
| UK 2026 | `uk2026.weinbender.io` | Google OAuth required, restricted to the existing email allowlist |
| API | Service token | `weinbender-io-api` token for programmatic access |