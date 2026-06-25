locals {
  app_yaml_files = fileset("${path.module}/../../../../apps", "*/app.yaml")

  app_yamls = {
    for f in local.app_yaml_files :
    split("/", f)[0] => yamldecode(file("${path.module}/../../../../apps/${f}"))
  }

  public_apps = {
    for name, y in local.app_yamls :
    name => merge(y.exposePublic, {
      release_name = try(y.releaseName, name)
      namespace    = try(y.namespace, name)
    })
    if try(y.exposePublic, null) != null
  }

  clusters_with_public_apps = toset([
    for _, v in local.public_apps : v.cluster
  ])

  # Extract the apex zone (last two labels) from each app's FQDN
  fqdn_apex_domains = toset([
    for _, app in local.public_apps :
    regex("([^.]+\\.[^.]+)$", app.fqdn)[0]
  ])
}

data "cloudflare_zone" "app_zones" {
  for_each = local.fqdn_apex_domains

  filter = {
    name = each.key
  }
}
