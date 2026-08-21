# terraform/cloudflare

Cloudflare resources for `weinbender.io` — Zero Trust Access, DNS, Tunnel.

## Resources

| File | Resources |
|------|-----------|
| `access.tf` | Google OAuth provider, existing Access policy data source, Access Application `uk2026.weinbender.io`, Service Token `weinbender-io-api` |
| `dns.tf` | CNAME records: `uk2026`, `helloworld` → Tunnel CNAME; `ntfy` → `docker0-lxc` Traefik gateway |
| `tunnel.tf` | Cloudflare Tunnel `weinbender-io` + config |

## Access Policy (uk2026.weinbender.io)

Access policies are managed in the Cloudflare dashboard. Terraform must not create,
update, or delete Access policies or their user membership rules; it should reference
existing policies with a `cloudflare_zero_trust_access_policy` data source.

The existing policy named `Me` is referenced by ID. Its users and rules are managed
entirely in the Cloudflare dashboard.

Service token `weinbender-io-api` for programmatic access.

The Google OAuth client credentials are sensitive Terraform variables and are
loaded by the shared GitHub Actions Terraform action from 1Password.

## DNS

**Current state:** most DNS records for `weinbender.io` are not managed in
Terraform; they are managed manually in the Cloudflare dashboard. The records
shown in `dns.tf` are only the Terraform-managed subset. Check the dashboard
before adding or changing a record to avoid creating a duplicate.

Tunnel-backed records point directly to the tunnel target:

```
uk2026.weinbender.io     CNAME <tunnel-id>.cfargotunnel.com
helloworld.weinbender.io CNAME <tunnel-id>.cfargotunnel.com
```

The ntfy service is LAN-backed by Traefik on `docker0-lxc`:

```
ntfy.weinbender.io CNAME docker0-lxc.weinbender.io
```

This record is intentionally unproxied. The `docker0-lxc.weinbender.io` gateway A
record must already point to the host's private LAN address.

Services exposed through a LAN Traefik gateway use a two-record chain instead:

```
<gateway>.weinbender.io  A      <gateway LAN IPv4 address>
<service>.weinbender.io  CNAME  <gateway>.weinbender.io
```

Create the gateway A record as soon as the gateway LXC is provisioned and its
LAN IPv4 address is known. This is an explicit provisioning follow-up and is
not an Ansible task; do not try to automate it through Ansible. Add each
service CNAME when the service is assigned to that gateway.

When these records are managed in Terraform, keep them in `dns.tf`, set
`proxied = false`, and use `ttl = 1`. Otherwise create the same pair manually
in the Cloudflare dashboard. The A record is required even though the zone is
public: the private address is intentional because the gateway is reachable
only from the LAN/VPN. The CNAME hostname must exactly match the hostname in
the Traefik `Host(...)` rule. Never substitute the tunnel target for the
gateway hostname in this path.

Example:

```hcl
resource "cloudflare_dns_record" "traefik_lan" {
  zone_id = var.cloudflare_zone_id
  name    = "traefik-lan"
  content = "192.168.1.20"
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "myservice" {
  zone_id = var.cloudflare_zone_id
  name    = "myservice"
  content = "traefik-lan.weinbender.io"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}
```

Replace the example hostname and address with the actual gateway and service;
do not commit runtime credentials or apply Terraform without reviewing the
plan.

## Backend

S3: `tf-backend-61rckk` / `cloudflare.tfstate`

## Auth

Cloudflare API token from 1Password: `op://network/cloudflare-terraform/credential`

Google OAuth credentials from 1Password:
- Client ID: `op://network/cloudflare-google-oauth/client-id`
- Client secret: `op://network/cloudflare-google-oauth/client-secret`

Create a Google OAuth web application before applying this component. After the
identity provider exists, add Cloudflare Access's generated redirect URL to the
Google OAuth client's authorized redirect URIs. The redirect URL is exposed as
`cloudflare_zero_trust_access_identity_provider.google.config[0].redirect_url`
after the provider is created; obtain it from the Cloudflare dashboard or the
Terraform state/outputs without committing it.

## Deploy

```bash
cd terraform/cloudflare
terraform init
terraform plan
terraform apply
```

**Note**: Tunnel token is NOT output by Terraform. After apply, retrieve from Cloudflare Zero Trust dashboard → Networks → Tunnels → weinbender-io → Configure → copy token → store in 1Password at `op://network/cloudflare-tunnel-weinbender-io/credential` for compose-stack deployment.