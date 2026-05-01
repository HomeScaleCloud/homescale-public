resource "helm_release" "rancher" {
  repository       = "https://releases.rancher.com/server-charts/stable"
  chart            = "rancher"
  name             = "rancher"
  version          = "2.14.1"
  namespace        = "cattle-system"
  create_namespace = true
  values = [
    yamlencode({
      hostname = "xxx"
      replicas = 2
      ingress = {
        enabled = false
        source  = "secret"
      }
      tls = "external"
    })
  ]
}

resource "kubernetes_manifest" "gitrepo_apps_mgmt" {
  depends_on = [helm_release.rancher]
  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"
    metadata = {
      name      = "apps-mgmt"
      namespace = "fleet-local"
    }
    spec = {
      repo            = "https://github.com/HomeScaleCloud/homescale"
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
