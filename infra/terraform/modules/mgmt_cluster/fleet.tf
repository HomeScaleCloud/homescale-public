resource "kubernetes_manifest" "gitrepo_apps_prod" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt, digikubernetes_namespace_v1.prod]
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
}

resource "kubernetes_manifest" "gitrepo_apps_test" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt, kubernetes_namespace_v1.test]
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
}

resource "kubernetes_manifest" "gitrepo_apps_lab" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt, kubernetes_namespace_v1.lab]
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
}

resource "kubernetes_manifest" "gitrepo_apps_mgmt" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt, kubernetes_namespace_v1.lab]
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
}
