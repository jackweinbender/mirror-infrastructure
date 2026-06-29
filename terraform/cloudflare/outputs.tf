output "tunnel_id" {
  description = "Cloudflare Tunnel ID -- CNAME target is <tunnel_id>.cfargotunnel.com"
  value       = cloudflare_zero_trust_tunnel_cloudflared.main.id
}
