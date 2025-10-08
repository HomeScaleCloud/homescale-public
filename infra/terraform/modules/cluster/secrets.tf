data "onepassword_vault" "cluster" {
  name = var.cluster
}

data "onepassword_item" "onepassword" {
  vault = var.cluster
  title = "onepassword"
}

# resource "kubernetes_secret" "onepassword_creds" {
#   metadata {
#     name      = "onepassword"
#     namespace = "onepassword"
#   }
#   data = {
#     operator-token = data.onepassword_item.onepassword.password
#     connect-credentials = data.onepassword_item.onepassword.credential
#   }
# }

resource "onepassword_item" "tailscale_k8s_operator" {
  vault    = data.onepassword_vault.cluster.uuid
  title    = "tailscale"
  username = tailscale_oauth_client.k8s_operator.id
  password = tailscale_oauth_client.k8s_operator.key
}

resource "onepassword_item" "talosconfig" {
  count    = var.store_talosconfig ? 1 : 0
  vault    = data.onepassword_vault.cluster.uuid
  title    = "talosconfig"
  password = data.talos_client_configuration.controlplane.talos_config
}

resource "onepassword_item" "kubeconfig" {
  count    = var.store_kubeconfig ? 1 : 0
  vault    = data.onepassword_vault.cluster.uuid
  title    = "kubeconfig"
  password = talos_cluster_kubeconfig.cluster.kubeconfig_raw
}