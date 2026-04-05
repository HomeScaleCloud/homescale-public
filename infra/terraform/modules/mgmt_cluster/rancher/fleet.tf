resource "kubernetes_manifest" "gitrepo_apps_prod" {
  depends_on = [kubernetes_namespace_v1.prod]
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps"
      namespace = "prod"
    }
    spec = {
      repo            = "https://github.com/HomeScaleCloud/homescale-public"
      branch          = "main"
      paths           = ["apps/*"]
      pollingInterval = "3m"
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
  depends_on = [kubernetes_namespace_v1.lab]

  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps"
      namespace = "lab"
    }
    spec = {
      repo            = "https://github.com/HomeScaleCloud/homescale-public"
      branch          = "main"
      paths           = ["apps/*"]
      pollingInterval = "3m"
      correctDrift = {
        enabled = true
      }
    }
  }
  field_manager {
    force_conflicts = true
  }
}
