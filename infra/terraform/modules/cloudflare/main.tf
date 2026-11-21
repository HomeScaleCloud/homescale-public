locals {
  cloudflare_yaml_files = fileset("${path.module}/../../../../apps", "*/cloudflare.yaml")

  cloudflare_yamls = {
    for f in local.cloudflare_yaml_files :
    split("/", f)[0] => yamldecode(file("${path.module}/../../../../apps/${f}"))
  }

  # One entry per exposePublic list item — the granularity cloudflared ingress
  # rules (hostname + optional path) need. Keyed per app+index, not fqdn:
  # multiple entries can share one hostname (different paths routed to
  # different backend services).
  public_apps = {
    for entry in flatten([
      for name, y in local.cloudflare_yamls : [
        for idx, e in try(y.expose, []) : merge(e, {
          app       = name
          namespace = try(e.namespace, name)
          key       = "${name}-${idx}"
        })
      ]
    ]) : entry.key => entry
  }

  # One entry per unique fqdn — the granularity DNS records, Cloudflare
  # Access applications and cache-bypass rules actually operate at. Several
  # public_apps path rules can share an fqdn; they share one DNS
  # record/Access app/cache setting too, so any one of them stands in here.
  public_hostnames = {
    for fqdn in distinct([for _, app in local.public_apps : app.fqdn]) :
    fqdn => [for _, app in local.public_apps : app if app.fqdn == fqdn][0]
  }

  clusters_with_public_apps = toset([
    for _, v in local.public_hostnames : v.env
  ])

  # Extract the apex zone (last two labels) from each app's FQDN
  fqdn_apex_domains = toset([
    for fqdn, _ in local.public_hostnames :
    regex("([^.]+\\.[^.]+)$", fqdn)[0]
  ])
}

data "cloudflare_zone" "app_zones" {
  for_each = local.fqdn_apex_domains

  filter = {
    name = each.key
  }
}
