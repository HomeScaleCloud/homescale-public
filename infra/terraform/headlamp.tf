# Clusters Headlamp federates into its cluster picker, alongside its own
# in-cluster context. Every Omni-managed cluster (each clusters/*/ dir with a
# cluster.yaml) is included automatically: its apiserver trusts the shared OIDC
# issuer via infra/omni/patches/base.yaml, and Headlamp reaches it over the
# tailnet (sidecar in apps/headlamp/app.yaml) at k8s.api.<cluster>REDACTED.
# mgmt has no cluster.yaml (Vultr VKE, not Omni), so it is excluded here and
# served as Headlamp's in-cluster context instead.
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
