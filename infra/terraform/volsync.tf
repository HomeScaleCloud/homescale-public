locals {
  # Apps that have a VolSync backup configured
  volsync_app_names = toset([
    for f in fileset("${path.root}/../../apps", "*/templates/volsync.yaml") :
    split("/", f)[0]
  ])
  volsync_app_configs = {
    for app in local.volsync_app_names :
    app => yamldecode(file("${path.root}/../../apps/${app}/app.yaml"))
  }
  volsync_cluster_names = toset([
    for f in fileset("${path.root}/../../clusters", "*/apps.yaml") :
    split("/", f)[0]
  ])
  volsync_deployments = {
    for pair in flatten([
      for app, config in local.volsync_app_configs : [
        for cluster in local.volsync_cluster_names : {
          key     = "${cluster}/${app}"
          app     = app
          cluster = cluster
        }
        if try(config.clusters[cluster].deploy, try(config.defaultDeploy, false))
      ]
    ]) : pair.key => pair
  }
}

resource "infisical_secret" "volsync_repository" {
  for_each = local.volsync_deployments

  name         = "RESTIC_REPOSITORY"
  value        = "$${prod.k8s.volsync.RESTIC_REPOSITORY}/${each.value.cluster}/${each.value.app}"
  env_slug     = "prod"
  workspace_id = module.infisical.project_id
  folder_path  = "/k8s/volsync/${each.value.cluster}/${each.value.app}"
}
