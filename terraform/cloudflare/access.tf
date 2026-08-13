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
  name       = "Allow Google users"
  decision   = "allow"

  include = [{ everyone = {} }]

  # The dashboard owns the user allowlist. Keep this configuration as a
  # placeholder for new policy creation without reconciling existing members.
  lifecycle {
    ignore_changes = [include]
  }

  # Require users to authenticate with Google instead of allowing Cloudflare's
  # one-time PIN flow.
  require = [{
    login_method = {
      id = cloudflare_zero_trust_access_identity_provider.google.id
    }
  }]
}

# ── Service token (programmatic access, day-two) ──────────────────────────────

resource "cloudflare_zero_trust_access_service_token" "api" {
  account_id = var.cloudflare_account_id
  name       = "weinbender-io-api"
}
