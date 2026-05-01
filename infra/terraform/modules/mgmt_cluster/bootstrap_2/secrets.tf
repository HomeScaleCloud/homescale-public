data "onepassword_vault" "k8s" {
  name = "k8s"
}

data "onepassword_item" "onepassword" {
  vault = "k8s"
  title = "onepassword"
}

resource "kubernetes_secret_v1" "onepassword" {

  metadata {
    name      = "onepassword"
    namespace = "onepassword"
  }
  data = {
    credential = data.onepassword_item.onepassword.credential
    password   = data.onepassword_item.onepassword.password
  }
}
