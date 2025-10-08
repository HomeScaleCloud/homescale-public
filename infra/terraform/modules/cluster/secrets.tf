data "onepassword_vault" "cluster" {
  name = var.cluster
}

data "onepassword_item" "onepassword" {
  vault = var.cluster
  title = "onepassword"
}

data "onepassword_item" "argocd_oidc" {
  vault = "common"
  title = "argocd-oidc"
}

data "onepassword_item" "entra_tenant" {
  vault = "common"
  title = "entra-tenant"
}

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