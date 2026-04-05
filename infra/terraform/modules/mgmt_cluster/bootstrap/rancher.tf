resource "helm_release" "rancher" {
  repository       = "https://releases.rancher.com/server-charts/stable"
  chart            = "rancher"
  name             = "rancher"
  version          = "2.13.3"
  namespace        = "cattle-system"
  create_namespace = true
  values = [
    yamlencode({
      hostname = "mgmt.homescale.cloud"
      replicas = 2
      ingress = {
        enabled = true
        source  = "secret"
      }
      tls = "external"
    })
  ]
}

resource "rancher2_bootstrap" "mgmt" {
  depends_on       = [data.kubernetes_secret_v1.rancher_bootstrap]
  initial_password = data.kubernetes_secret_v1.rancher_bootstrap.data["bootstrapPassword"]
}

resource "kubernetes_manifest" "gitrepo_apps_mgmt" {
  depends_on = [helm_release.rancher]
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
      correctDrift = {
        enabled = true
      }
    }
  }
  field_manager {
    force_conflicts = true
  }
}
