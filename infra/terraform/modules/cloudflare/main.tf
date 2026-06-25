data "cloudflare_zone" "homescale" {
  zone_id = var.zone_id
}

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
}
