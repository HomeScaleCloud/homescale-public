resource "kubernetes_manifest" "gitrepo_apps_prod" {
  depends_on = [kubernetes_namespace_v1.prod]
  count      = var.bootstrapped ? 1 : 0
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
    }
  }
  field_manager {
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "gitrepo_apps_test" {
  depends_on = [kubernetes_namespace_v1.test]
  count      = var.bootstrapped ? 1 : 0
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps"
      namespace = "test"
    }
    spec = {
      repo            = "https://github.com/HomeScaleCloud/homescale-public"
      branch          = "main"
      paths           = ["apps/*"]
      pollingInterval = "3m"
    }
  }
  field_manager {
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "gitrepo_apps_lab" {
  depends_on = [kubernetes_namespace_v1.lab]
  count      = var.bootstrapped ? 1 : 0
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
    }
  }
  field_manager {
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "gitrepo_apps_mgmt" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  count      = var.bootstrapped ? 1 : 0
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps"
      namespace = "fleet-local"
    }
    spec = {
      repo            = "https://github.com/HomeScaleCloud/homescale-public"
      branch          = "main"
      paths           = ["apps/*"]
      pollingInterval = "3m"
    }
  }
  field_manager {
    force_conflicts = true
  }
}
