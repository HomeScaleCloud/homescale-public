

resource "kubernetes_namespace" "onepassword" {
  metadata { name = "onepassword" }
}

resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s-${var.region}"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator", "tag:app", "tag:k8s-api"]
}

locals {
  apps = {
    # name = { chart, version, namespace, parameters?, valuesObject? }
    "cert-manager" = {
      chart     = "cert-manager"
      version   = "0.1.0"
      namespace = "cert-manager"
    }

    "external-dns" = {
      chart     = "external-dns"
      version   = "0.1.0"
      namespace = "external-dns"
    }

    "ingress-nginx" = {
      chart     = "ingress-nginx"
      version   = "0.1.0"
      namespace = "ingress-nginx"
      parameters = [
        {
          name  = "ingress-nginx.controller.service.annotations.tailscale.com/hostname"
          value = "ingress-${var.region}"
        }
      ]
    }

    "librespeed" = {
      chart     = "librespeed"
      version   = "0.1.0"
      namespace = "librespeed"
      parameters = [
        {
          name  = "ingress.host"
          value = "speedtest.${var.region}.homescale.cloud"
        }
      ]
    }

    "metrics" = {
      chart     = "metrics"
      version   = "0.1.0"
      namespace = "monitoring"
      parameters = [
        {
          name  = "kube-prometheus-stack.grafana.ingress.hosts[0]"
          value = "metrics.${var.region}.homescale.cloud"
        },
        {
          name  = "kube-prometheus-stack.grafana.ingress.tls.hosts[0]"
          value = "metrics.${var.region}.homescale.cloud"
        },
        {
          name  = "kube-prometheus-stack.grafana.grafana.ini.server.root_url"
          value = "metrics.${var.region}.homescale.cloud"
        }
      ]
    }

    "nfd" = {
      chart     = "nfd"
      version   = "0.1.0"
      namespace = "node-feature-discovery"
    }

    "onepassword" = {
      chart     = "onepassword"
      version   = "0.1.0"
      namespace = "onepassword"
    }

    "rbac" = {
      chart     = "rbac"
      version   = "0.1.0"
      namespace = "rbac"
    }

    "tailscale" = {
      chart     = "tailscale"
      version   = "0.1.0"
      namespace = "tailscale"
      parameters = [
        {
          name  = "tailscale-operator.operatorConfig.hostname"
          value = "k8s-${var.region}"
        },
        {
          name  = "operatorOauth.secretPath"
          value = "vaults/${var.region}/items/onepassword"
        }
      ]
    }

    "trivy-operator" = {
      chart     = "trivy-operator"
      version   = "0.1.0"
      namespace = "trivy-system"
    }
  }
}

resource "kubernetes_manifest" "apps" {
  for_each = local.apps

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.key
      namespace = "default"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "oci://ghcr.io/homescalecloud/helm"
        chart          = each.value.chart
        targetRevision = each.value.version

        helm = merge(
          {},
          length(lookup(each.value, "parameters", [])) > 0 ? {
            parameters = lookup(each.value, "parameters", [])
          } : {},
          length(lookup(each.value, "valuesObject", {})) > 0 ? {
            valuesObject = lookup(each.value, "valuesObject", {})
          } : {}
        )
      }
        destination = {
            server = "https://kubernetes.default.svc"
            namespace = each.value.namespace
        }

        syncPolicy = {
            automated = {
            prune    = true
            selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
        }
    }
  }
}