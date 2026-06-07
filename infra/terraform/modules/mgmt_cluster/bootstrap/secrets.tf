data "onepassword_item" "k8s_deploy_key" {
  vault = "k8s"
  title = "homescale-k8s-deploy-key"
}

data "onepassword_item" "onepassword" {
  vault = "k8s"
  title = "onepassword"
}

resource "kubernetes_secret_v1" "k8s_deploy_key" {
  metadata {
    name      = "homescale-k8s-deploy-key"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    url           = "git@github.com:HomeScaleCloud/homescale.git"
    sshPrivateKey = base64decode(data.onepassword_item.k8s_deploy_key.password)
  }
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
