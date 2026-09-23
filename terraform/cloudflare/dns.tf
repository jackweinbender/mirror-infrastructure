resource "cloudflare_dns_record" "uk2026" {
  zone_id = var.cloudflare_zone_id
  name    = "uk2026"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "helloworld" {
  zone_id = var.cloudflare_zone_id
  name    = "helloworld"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "ntfy" {
  zone_id = var.cloudflare_zone_id
  name    = "ntfy"
  content = "docker0-lxc.weinbender.io"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "crow" {
  zone_id = var.cloudflare_zone_id
  name    = "crow"
  content = "docker0-lxc.weinbender.io"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "uptime_kuma" {
  zone_id = var.cloudflare_zone_id
  name    = "uptime-kuma"
  content = "docker0-lxc.weinbender.io"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana"
  content = "docker0-lxc.weinbender.io"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "paseo" {
  zone_id = var.cloudflare_zone_id
  name    = "paseo"
  content = "docker0-lxc.weinbender.io"
  type    = "CNAME"
  proxied = false
  ttl     = 1
}
