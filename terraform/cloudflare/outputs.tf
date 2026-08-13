output "tunnel_id" {
  description = "Cloudflare Tunnel ID -- CNAME target is <tunnel_id>.cfargotunnel.com"
  value       = cloudflare_zero_trust_tunnel_cloudflared.main.id
}

output "google_access_redirect_url" {
  description = "Authorized redirect URI to add to the Google OAuth client"
  value       = cloudflare_zero_trust_access_identity_provider.google.config[0].redirect_url
}
