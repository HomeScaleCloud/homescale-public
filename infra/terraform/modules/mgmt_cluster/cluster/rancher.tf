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
        enabled = false
        source  = "secret"
      }
      tls = "external"
    })
  ]
}
