data "kubernetes_secret_v1" "rancher_bootstrap" {
  metadata {
    name      = "bootstrap-secret"
    namespace = "cattle-system"
  }
}

data "onepassword_vault" "github_actions" {
  name = "github-actions"
}

resource "onepassword_item" "rancher" {
  vault    = data.onepassword_vault.github_actions.uuid
  title    = "rancher"
  password = rancher2_bootstrap.mgmt.token
}
