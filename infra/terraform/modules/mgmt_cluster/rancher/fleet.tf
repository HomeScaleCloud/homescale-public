resource "kubernetes_manifest" "gitrepo_apps_prod" {
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps-prod"
      namespace = "prod"
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

resource "kubernetes_manifest" "gitrepo_apps_lab" {
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps-lab"
      namespace = "lab"
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
