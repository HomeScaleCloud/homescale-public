data "onepassword_vault" "k8s" {
  name = "k8s"
}

data "onepassword_vault" "github_actions" {
  name = "github-actions"
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

locals {
  homescale_k8s_deploy_key_namespaces = toset([
    "fleet-local",
    "prod",
    "lab",
  ])
}

resource "tls_private_key" "homescale_k8s_deploy_key" {
  algorithm = "ED25519"
}

resource "kubernetes_secret_v1" "homescale_k8s_deploy_key" {
  for_each = local.homescale_k8s_deploy_key_namespaces

  metadata {
    name      = "homescale-k8s-deploy-key"
    namespace = each.value
  }

  type = "kubernetes.io/ssh-auth"

  data = {
    "ssh-privatekey" = tls_private_key.homescale_k8s_deploy_key.private_key_pem
  }

  depends_on = [
    kubernetes_namespace_v1.prod,
    kubernetes_namespace_v1.lab,
  ]
}

resource "onepassword_item" "homescale_k8s_deploy_key" {
  vault    = data.onepassword_vault.github_actions.uuid
  title    = "homescale-k8s-deploy-key"
  password = tls_private_key.homescale_k8s_deploy_key.public_key_openssh
}
