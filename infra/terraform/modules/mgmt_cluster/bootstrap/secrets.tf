resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace_v1" "infisical" {
  metadata {
    name = "infisical"
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }
}

resource "kubernetes_secret_v1" "argocd_deploy_key" {
  metadata {
    name      = "homescale-k8s-deploy-key"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    url           = "git@github.com:HomeScaleCloud/homescale.git"
    sshPrivateKey = var.argocd_deploy_key
  }
  lifecycle {
    # Infisical operator owns this secret after bootstrap — prevent Terraform drift fights
    ignore_changes = [data]
  }
}

resource "kubernetes_secret_v1" "infisical_operator" {
  metadata {
    name      = "infisical-operator-auth"
    namespace = kubernetes_namespace_v1.infisical.metadata[0].name
  }
  data = {
    clientId     = var.infisical_k8s_operator_client_id
    clientSecret = var.infisical_k8s_operator_client_secret
  }
}
