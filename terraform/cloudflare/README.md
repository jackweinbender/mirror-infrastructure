# terraform/cloudflare

Cloudflare resources for `weinbender.io` — Zero Trust Access, DNS, Tunnel.

## Resources

| File | Resources |
|------|-----------|
| `access.tf` | Google OAuth provider, existing Access policy data source, Access Application `uk2026.weinbender.io`, Service Token `weinbender-io-api` |
| `dns.tf` | CNAME records: `uk2026`, `helloworld` → Tunnel CNAME |
| `tunnel.tf` | Cloudflare Tunnel `weinbender-io` + config |

## Access Policy (uk2026.weinbender.io)

The existing Access policy named `Me` is referenced by ID. Its users and rules are
managed entirely in the Cloudflare dashboard; Terraform does not create, update, or
delete the policy.

Service token `weinbender-io-api` for programmatic access.

The Google OAuth client credentials are sensitive Terraform variables and are
loaded by the shared GitHub Actions Terraform action from 1Password.

## DNS

Records point to tunnel:
```
uk2026.weinbender.io     CNAME <tunnel-id>.cfargotunnel.com
helloworld.weinbender.io CNAME <tunnel-id>.cfargotunnel.com
```

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