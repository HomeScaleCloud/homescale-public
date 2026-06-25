resource "infisical_secret" "tunnel_credentials" {
  for_each = local.clusters_with_public_apps

  name = "TUNNEL_CREDENTIALS"
  value = jsonencode({
    AccountTag   = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].account_tag
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id
    TunnelSecret = random_bytes.tunnel_secret[each.key].base64
  })
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/cloudflared/${each.key}"
}
