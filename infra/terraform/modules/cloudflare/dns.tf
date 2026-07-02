locals {
  app_zone_ids = {
    for fqdn, app in local.public_apps :
    fqdn => data.cloudflare_zone.app_zones[regex("([^.]+\\.[^.]+)$", fqdn)[0]].zone_id
  }
}

resource "cloudflare_dns_record" "public_app" {
  for_each = local.public_apps

  zone_id = local.app_zone_ids[each.key]
  name    = each.value.fqdn
  content = "${cloudflare_zero_trust_tunnel_cloudflared.cluster[each.value.cluster].id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
