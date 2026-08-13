# ── Google OAuth ───────────────────────────────────────────────────────────────

resource "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id = var.cloudflare_account_id
  name       = "Google"
  type       = "google"

  config = {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}

# ── Existing Access policy ────────────────────────────────────────────────────

# User membership and policy rules are managed in the Cloudflare dashboard.
data "cloudflare_zero_trust_access_policy" "me" {
  account_id = var.cloudflare_account_id
  policy_id  = "b12aa35b-95c5-484d-97b5-217c08a714e9"
}

# ── uk2026.weinbender.io ─────────────────────────────────────────────────────

resource "cloudflare_zero_trust_access_application" "uk2026" {
  zone_id          = var.cloudflare_zone_id
  name             = "UK 2026"
  domain           = "uk2026.weinbender.io"
  session_duration = "504h"
  type             = "self_hosted"

  policies = [{
    id         = data.cloudflare_zero_trust_access_policy.me.id
    precedence = 1
  }]
}

# ── Service token (programmatic access, day-two) ──────────────────────────────

resource "cloudflare_zero_trust_access_service_token" "api" {
  account_id = var.cloudflare_account_id
  name       = "weinbender-io-api"
}
