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
