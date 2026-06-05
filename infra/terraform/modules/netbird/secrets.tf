data "onepassword_vault" "github_actions" {
  name = "github-actions"
}

data "onepassword_vault" "k8s" {
  name = "k8s"
}

resource "onepassword_item" "netbird_k8s_operator" {
  vault    = data.onepassword_vault.k8s.uuid
  title    = "netbird"
  password = netbird_token.k8s_operator.token
}
