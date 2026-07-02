resource "random_bytes" "tunnel_secret" {
  for_each = local.clusters_with_public_apps
  length   = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  for_each = local.clusters_with_public_apps

  account_id    = values(data.cloudflare_zone.app_zones)[0].account.id
  name          = "homescale-${each.key}"
  tunnel_secret = random_bytes.tunnel_secret[each.key].base64
  config_src    = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  for_each = local.clusters_with_public_apps

  account_id = values(data.cloudflare_zone.app_zones)[0].account.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id

  config = {
    ingress = concat(
      [for fqdn, app in local.public_apps : {
        hostname = app.fqdn
        service  = "http://${app.service}.${app.namespace}.svc.cluster.local:${app.port}"
      } if app.cluster == each.key],
      [{ service = "http_status:404" }]
    )
  }
}
