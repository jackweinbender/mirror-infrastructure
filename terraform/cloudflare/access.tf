# ── Home Assistant Access application ────────────────────────────────────────

resource "cloudflare_zero_trust_access_application" "homeassistant" {
  zone_id          = var.cloudflare_zone_id
  name             = "Home Assistant"
  domain           = "ha.weinbender.io"
  session_duration = "24h"
  type             = "self_hosted"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.homeassistant_allow.id
    precedence = 1
  }]
}

# NOTE: Google OAuth identity provider must be configured manually in the
# Cloudflare Zero Trust UI before this policy will function. Navigate to
# Settings -> Authentication -> Add new identity provider -> Google. This
# is a one-time manual step; it is not managed by Terraform in this root.
#
# In v5, policies are account-scoped standalone resources referenced by ID
# from the application. application_id is no longer an attribute.
resource "cloudflare_zero_trust_access_policy" "homeassistant_allow" {
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
