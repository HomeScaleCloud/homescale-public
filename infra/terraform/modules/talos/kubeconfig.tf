# Break-glass admin kubeconfig (client-cert auth, bypasses OIDC entirely) —
# the Terraform-era equivalent of `omnictl kubeconfig --break-glass`. Day-to-
# day human/CI access still goes through the direct-OIDC path described in
# CLAUDE.md's Networking section (Tailscale apiserver-proxy), unchanged by
# this module. Stored in Infisical purely for disaster-recovery access when
# OIDC/Tailscale itself is unavailable — nothing in this repo reads it back.
#
# A resource, not a data source: the data-source form is deprecated in this
# provider version (slated for removal) in favor of this resource, which also
# auto-renews the underlying client cert (certificate_renewal_duration,
# default 720h) instead of only ever reading whatever was valid at apply time.
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_nodes[0].ip
}

resource "infisical_secret" "kubeconfig" {
  name         = "KUBECONFIG"
  value        = talos_cluster_kubeconfig.this.kubeconfig_raw
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/talos/${var.cluster_name_short}"
}
