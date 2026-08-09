# Clusters Headlamp shows in its cluster picker, alongside its own in-cluster
# one (mgmt) — derived from clusters/*/cluster.yaml rather than a hand-maintained
# list, so a cluster shows up automatically once its kube-apiserver is set up to
# trust the shared OIDC issuer (i.e. once its cluster.yaml references
# infra/omni/patches/oidc.yaml). See apps/headlamp/templates/kubeconfig-secret.yaml.
locals {
  headlamp_cluster_files = fileset("${path.module}/../../clusters", "*/cluster.yaml")

  headlamp_clusters = sort([
    for f in local.headlamp_cluster_files :
    split("/", f)[0]
    if split("/", f)[0] != "mgmt" && strcontains(file("${path.module}/../../clusters/${f}"), "patches/oidc.yaml")
  ])
}

resource "infisical_secret" "headlamp_clusters" {
  name         = "HEADLAMP_CLUSTERS"
  value        = join(",", local.headlamp_clusters)
  env_slug     = "prod"
  workspace_id = module.infisical.project_id
  folder_path  = "/k8s/oidc"
}
