# Every Omni-managed cluster (clusters/*/cluster.yaml) is federated into
# Headlamp's cluster picker. mgmt has no cluster.yaml (Vultr VKE, not Omni), so
# it's excluded here and served as Headlamp's in-cluster context instead.
locals {
  headlamp_clusters = sort([
    for f in fileset("${path.module}/../../clusters", "*/cluster.yaml") :
    split("/", f)[0]
  ])
}

resource "infisical_secret" "headlamp_clusters" {
  name         = "HEADLAMP_CLUSTERS"
  value        = join(",", local.headlamp_clusters)
  env_slug     = "prod"
  workspace_id = module.infisical.project_id
  folder_path  = "/k8s/oidc"
}
