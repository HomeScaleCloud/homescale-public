# Blocks on cluster health before anything downstream (e.g. the kubeconfig
# fetch below) treats this cluster as ready. No direct Omni-dashboard
# equivalent — this is a point-in-time check during apply, not a standing
# metric; cluster health monitoring post-bootstrap is Prometheus's job
# (apps/metrics), unchanged by this module.
#
# Always targets each node's static `ip`, never `bootstrap_ip` — so on a brand
# new machine's very first apply (before it's actually settled on its static
# address), this is expected to fail/time out. That's fine: re-run `terraform
# apply` once the operator has confirmed the node answers at `ip`, same as
# every other steady-state reference in this module (kubeconfig.tf,
# client_config.tf). See the control_plane_nodes variable.
data "talos_cluster_health" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for n in var.control_plane_nodes : n.ip]
  worker_nodes         = [for n in var.worker_nodes : n.ip]
  endpoints            = [for n in var.control_plane_nodes : n.ip]
}
