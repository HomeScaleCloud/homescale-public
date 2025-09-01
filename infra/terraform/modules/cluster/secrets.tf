data "onepassword_vault" "region" {
  name = var.region
}

data "onepassword_item" "tailscale" {
  vault = "${var.region}"
  title = "tailscale"
}

data "onepassword_item" "onepassword" {
  vault = "${var.region}"
  title = "onepassword"
}

resource "kubernetes_secret" "onepassword_creds" {
  metadata {
    name      = "onepassword"
    namespace = "onepassword"
  }
  data = {
    operator-token = data.onepassword_item.onepassword.password
    connect-credentials = data.onepassword_item.onepassword.credential
  }
}

resource "onepassword_item" "tailscale_k8s_operator" {
  vault    = data.onepassword_vault.region.uuid
  title    = "tailscale"
  username = tailscale_oauth_client.k8s_operator.id
  password = tailscale_oauth_client.k8s_operator.key
}