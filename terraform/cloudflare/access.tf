# ── uk2026.weinbender.io ─────────────────────────────────────────────────────

resource "cloudflare_zero_trust_access_application" "uk2026" {
  zone_id          = var.cloudflare_zone_id
  name             = "UK 2026"
  domain           = "uk2026.weinbender.io"
  session_duration = "24h"
  type             = "self_hosted"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow.id
    precedence = 1
  }]
}

resource "cloudflare_zero_trust_access_policy" "allow" {
  account_id = var.cloudflare_account_id
  name       = "Allow whitelisted Google accounts"
  decision   = "allow"

  include = [{
    email = {
      email = "jack.weinbender@gmail.com"
    }
  }]
}

# ── Service token (programmatic access, day-two) ──────────────────────────────

resource "cloudflare_zero_trust_access_service_token" "api" {
  account_id = var.cloudflare_account_id
  name       = "weinbender-io-api"
}
