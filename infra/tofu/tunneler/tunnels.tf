resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  for_each = local.clusters_with_public_apps

  account_id    = values(data.cloudflare_zone.app_zones)[0].account.id
  name          = "homescale-${each.key}"
  tunnel_secret = data.infisical_secrets.cloudflare_tunnel_secrets.secrets["TUNNEL_SECRET_${upper(each.key)}"].value
  config_src    = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  for_each = local.clusters_with_public_apps

  account_id = values(data.cloudflare_zone.app_zones)[0].account.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id

  config = {
    ingress = concat(
      [for _, app in local.public_apps : {
        hostname = app.fqdn
        path     = try(app.path, null)
        service  = "${try(app.tls, false) ? "https" : "http"}://${app.service}.${app.namespace}.svc.cluster.local:${app.port}"
        origin_request = try(app.tls, false) ? {
          # Backend cert's SANs cover app.fqdn, not the in-cluster Service DNS name.
          origin_server_name = app.fqdn
        } : null
      } if app.env == each.key],
      [{ service = "http_status:404" }]
    )
  }
}
