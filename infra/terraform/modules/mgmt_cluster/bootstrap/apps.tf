resource "kubernetes_manifest" "apps" {
  manifest = yamldecode(file("${path.module}/../../../../../clusters/mgmt/apps.yaml"))
}
