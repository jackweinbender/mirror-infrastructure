# ── Google OAuth ───────────────────────────────────────────────────────────────

resource "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id = var.cloudflare_account_id
  name       = "Google"
  type       = "google"

  config {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}

# ── uk2026.weinbender.io ─────────────────────────────────────────────────────

resource "cloudflare_zero_trust_access_application" "uk2026" {
  zone_id          = var.cloudflare_zone_id
  name             = "UK 2026"
  domain           = "uk2026.weinbender.io"
  session_duration = "504h"
  type             = "self_hosted"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow.id
    precedence = 1
  }]
}

resource "cloudflare_zero_trust_access_policy" "allow" {
  account_id = var.cloudflare_account_id
  name       = "Allow whitelisted emails via Google"
  decision   = "allow"

  include = [
    { email = { email = "jack.weinbender@gmail.com" } },
    { email = { email = "tiffany@idamayes.com" } },
    { email = { email = "jackweinbender@msn.com" } },
    { email = { email = "maryweinbender@msn.com" } },
    { email = { email = "jennwrites21@gmail.com" } },
    { email = { email = "kendramathews26@gmail.com" } },
    { email = { email = "sergio@cucinalogica.com" } },
    { email = { email = "jamiedel818@gmail.com" } },
    { email = { email = "adamlbean@gmail.com" } },
    { email = { email = "cj.frisina@gmail.com" } },
    { email = { email = "brandondwaite@proton.me" } },
    { email = { email = "tammath80@gmail.com" } },
  ]

  # Keep the existing email allowlist, but require users to authenticate with
  # Google instead of allowing Cloudflare's one-time PIN flow.
  require {
    login_method = [cloudflare_zero_trust_access_identity_provider.google.id]
  }
}

# ── Service token (programmatic access, day-two) ──────────────────────────────

resource "cloudflare_zero_trust_access_service_token" "api" {
  account_id = var.cloudflare_account_id
  name       = "weinbender-io-api"
}
