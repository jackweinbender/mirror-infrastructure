variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for weinbender.io (found in CF dashboard -> Overview)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID (found in CF dashboard -> Overview)"
  type        = string
}

variable "google_oauth_client_id" {
  description = "Google OAuth client ID used by Cloudflare Access"
  type        = string
  sensitive   = true
}

variable "google_oauth_client_secret" {
  description = "Google OAuth client secret used by Cloudflare Access"
  type        = string
  sensitive   = true
}
