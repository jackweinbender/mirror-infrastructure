# terraform/cloudflare

Cloudflare resources for `weinbender.io` — Zero Trust Access, DNS, Tunnel.

## Resources

| File | Resources |
|------|-----------|
| `access.tf` | Access Application `uk2026.weinbender.io` (email OTP allowlist), Service Token `weinbender-io-api` |
| `dns.tf` | CNAME records: `uk2026`, `helloworld` → Tunnel CNAME |
| `tunnel.tf` | Cloudflare Tunnel `weinbender-io` + config |

## Access Policy (uk2026.weinbender.io)

Allowlist (OTP email):
- `jack.weinbender@gmail.com`
- `tiffany@idamayes.com`
- `jackweinbender@msn.com`
- `maryweinbender@msn.com`
- `jennwrites21@gmail.com`
- `kendramathews26@gmail.com`
- `sergio@cucinalogica.com`
- `jamiedel818@gmail.com`
- `adamlbean@gmail.com`
- `cj.frisina@gmail.com`
- `brandondwaite@proton.me`
- `tammath80@gmail.com`

Service token `weinbender-io-api` for programmatic access.

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

## Deploy

```bash
cd terraform/cloudflare
terraform init
terraform plan
terraform apply
```

**Note**: Tunnel token is NOT output by Terraform. After apply, retrieve from Cloudflare Zero Trust dashboard → Networks → Tunnels → weinbender-io → Configure → copy token → store in 1Password at `op://network/cloudflare-tunnel-weinbender-io/credential` for compose-stack deployment.