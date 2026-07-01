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
  name       = "Allow whitelisted emails (OTP)"
  decision   = "allow"

  include = [
    { email_otp = { email = "jack.weinbender@gmail.com" } },
    { email_otp = { email = "tiffany@idamayes.com" } },
    { email_otp = { email = "jackweinbender@msn.com" } },
    { email_otp = { email = "maryweinbender@msn.com" } },
    { email_otp = { email = "jennwrites21@gmail.com" } },
    { email_otp = { email = "kendramathews26@gmail.com" } },
    { email_otp = { email = "sergio@cucinalogica.com" } },
    { email_otp = { email = "jamiedel818@gmail.com" } },
  ]
}

# ── Service token (programmatic access, day-two) ──────────────────────────────

resource "cloudflare_zero_trust_access_service_token" "api" {
  account_id = var.cloudflare_account_id
  name       = "weinbender-io-api"
}
