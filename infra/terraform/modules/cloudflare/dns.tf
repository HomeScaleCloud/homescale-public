resource "cloudflare_dns_record" "public_app" {
  for_each = local.public_apps

  zone_id = var.zone_id
  name    = each.value.fqdn
  content = "${cloudflare_zero_trust_tunnel_cloudflared.cluster[each.value.cluster].id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
