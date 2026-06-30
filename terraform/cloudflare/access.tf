# ── Service token (programmatic access, day-two) ──────────────────────────────

resource "cloudflare_zero_trust_access_service_token" "api" {
  account_id = var.cloudflare_account_id
  name       = "weinbender-io-api"
}
