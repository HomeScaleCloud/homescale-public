resource "kubernetes_manifest" "gitrepo_apps_mgmt" {
  depends_on = [kubernetes_secret_v1.homescale_k8s_deploy_key]
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps-mgmt"
      namespace = "fleet-local"
    }
    spec = {
      repo             = "git@github.com:HomeScaleCloud/homescale.git"
      clientSecretName = "homescale-k8s-deploy-key" #pragma: allowlist secret
      branch           = "main"
      paths            = ["apps/*"]
      pollingInterval  = "3m"
      correctDrift = {
        enabled = true
      }
    }
  }
  field_manager {
    force_conflicts = true
  }
}
