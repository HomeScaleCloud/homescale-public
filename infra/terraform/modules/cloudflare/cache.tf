locals {
  # exposePublic entries that opt out of Cloudflare's edge cache via `cacheBypass: true`.
  cache_bypass_apps = {
    for fqdn, app in local.public_apps :
    fqdn => app
    if try(app.cacheBypass, false)
  }

  cache_bypass_zone_ids = toset([
    for fqdn, app in local.cache_bypass_apps : local.app_zone_ids[fqdn]
  ])
}

# One http_request_cache_settings entry-point ruleset per zone (Cloudflare allows only
# one per zone/phase), containing one bypass rule per cacheBypass-opted-in hostname in
# that zone.
resource "cloudflare_ruleset" "cache_bypass" {
  for_each = local.cache_bypass_zone_ids

  zone_id     = each.key
  name        = "Bypass cache"
  description = "Bypass Cloudflare's edge cache for apps that opt out via exposePublic[].cacheBypass"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    for fqdn, app in local.cache_bypass_apps : {
      ref         = "bypass_cache_${replace(fqdn, ".", "_")}"
      description = "Bypass cache for ${fqdn}"
      expression  = "(http.host eq \"${fqdn}\")"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
    } if local.app_zone_ids[fqdn] == each.key
  ]
}
