resource "kubernetes_manifest" "gitrepo_apps_mgmt" {
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps-mgmt"
      namespace = "fleet-local"
    }
    spec = {
      repo             = "https://github.com/HomeScaleCloud/homescale"
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
