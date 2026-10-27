# talosconfig for this cluster — the client-auth equivalent of omnictl's
# break-glass kubeconfig path, for talosctl access straight to the nodes.
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = concat([for n in var.control_plane_nodes : n.ip], [for n in var.worker_nodes : n.ip])
  endpoints            = [for n in var.control_plane_nodes : n.ip]
}
