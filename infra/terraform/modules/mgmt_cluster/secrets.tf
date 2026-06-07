data "onepassword_vault" "github_actions" {
  name = "github-actions"
}

resource "onepassword_item" "kubeconfig" {
  vault    = data.onepassword_vault.github_actions.uuid
  title    = "mgmt-kubeconfig"
  password = digitalocean_kubernetes_cluster.mgmt.kube_config.0.raw_config
}
