resource "cloudflare_dns_record" "homeassistant" {
  zone_id = var.cloudflare_zone_id
  name    = "ha"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1 # 1 = automatic when proxied = true
}
