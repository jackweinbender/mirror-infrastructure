resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id    = var.cloudflare_account_id
  name          = "weinbender-io"
  config_src    = "cloudflare"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config = {
    ingress = [
      {
        # Wildcard public hostname — registers *.weinbender.io with Cloudflare's
        # edge so any subdomain CNAME'd to this tunnel is accepted. Traefik
        # receives the original Host header and routes to the right container.
        #
        # HTTP (not HTTPS) to Traefik: the CF tunnel already encrypts the
        # CF-edge→cloudflared leg; the cloudflared→Traefik hop is on a private
        # Docker network and doesn't need TLS. Using HTTPS here requires Traefik
        # to have a valid cert ready before cloudflared will connect, which
        # causes 502s on fresh deploys before ACME completes.
        hostname = "*.weinbender.io"
        service  = "http://traefik:80"
      },
      {
        # Required catch-all — Cloudflare rejects configs with no fallback.
        service = "http_status:404"
      }
    ]
  }
}
