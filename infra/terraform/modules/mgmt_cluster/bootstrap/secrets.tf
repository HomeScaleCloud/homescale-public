data "onepassword_vault" "k8s" {
  name = "k8s"
}

data "onepassword_item" "onepassword" {
  vault = "k8s"
  title = "onepassword"
}

data "onepassword_item" "twingate" {
  vault = "k8s"
  title = "tg-k8s-operator"
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

data "kubernetes_secret_v1" "rancher_bootstrap" {
  depends_on = [helm_release.rancher]
  metadata {
    name      = "bootstrap-secret"
    namespace = "cattle-system"
  }
}

resource "kubernetes_secret_v1" "twingate" {
  depends_on = [kubernetes_namespace_v1.twingate]
  metadata {
    name      = "tf-tg-k8s-operator"
    namespace = "twingate"
  }
  data = {
    credential = data.onepassword_item.twingate.credential
  }
}
