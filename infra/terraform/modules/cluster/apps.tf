resource "kubernetes_manifest" "argocd_app" {
  count      = (!var.init_stage_1 && !var.init_stage_2) ? 1 : 0
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "homescale-apps-${var.cluster}"
      namespace = "argocd"
      labels = {
        "cluster.homescale.cloud/name"   = var.cluster
        "cluster.homescale.cloud/region" = var.region
      }
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "ghcr.io/homescalecloud/helm"
        chart          = "homescale-apps"
        targetRevision = "0.1.0"
        helm = {
          valueFiles = [
            "values.yaml",
            "values-${var.cluster}.yaml"
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}
