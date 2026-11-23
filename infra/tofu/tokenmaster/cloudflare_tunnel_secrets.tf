locals {
  cluster_names = sort(distinct([
    for cluster_file in fileset("${path.module}/../../../clusters", "*/**") : split("/", cluster_file)[0]
  ]))
}

// One per cluster, minted unconditionally (cheap, unused if a cluster has no
// public apps yet) so tunneler never needs to recompute clusters_with_public_apps
// here — that would require reading apps/*/cloudflare.yaml and would create a
// cycle, since tunneler already depends on tokenmaster for its own bootstrap.
resource "random_bytes" "cloudflare_tunnel_secret" {
  for_each = toset(local.cluster_names)
  length   = 32
}

resource "infisical_secret" "cloudflare_tunnel_secret" {
  for_each = toset(local.cluster_names)

  name         = "TUNNEL_SECRET_${upper(each.key)}"
  value        = random_bytes.cloudflare_tunnel_secret[each.key].base64
  env_slug     = "prod"
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/k8s/cloudflare-tunnel"
}
