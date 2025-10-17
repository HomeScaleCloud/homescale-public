locals {
  apps_all = [
    {
      releaseName    = "cert-manager"
      chart          = "cert-manager"
      repoURL        = "https://charts.jetstack.io"
      targetRevision = "1.19.0"
      namespace      = "cert-manager"
      values = {
        crds = {
          enabled = true
        }
      }
      enabled = var.app_cert_manager_enabled
    },
    {
      releaseName    = "cert-manager-crs"
      chart          = "cert-manager-crs"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "cert-manager"
      enabled        = var.app_cert_manager_crs_enabled
    },
    {
      releaseName    = "external-dns"
      chart          = "external-dns"
      repoURL        = "https://kubernetes-sigs.github.io/external-dns/"
      targetRevision = "1.18.0"
      namespace      = "external-dns"
      values = {
        provider = {
          name = "cloudflare"
        }
        env = [
          {
            name = "CF_API_TOKEN"
            valueFrom = {
              secretKeyRef = {
                name = "op-cloudflare"
                key  = "credential"
              }
            }
          }
        ]
        domainFilters = ["homescale.cloud"]
      }
      enabled = var.app_external_dns_enabled
    },
    {
      releaseName    = "external-dns-crs"
      chart          = "external-dns-crs"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "external-dns"
      enabled        = var.app_external_dns_crs_enabled
    },
    {
      releaseName    = "generic-device-plugin"
      chart          = "generic-device-plugin"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "kube-system"
      enabled        = var.app_generic_device_plugin_enabled
    },
    {
      releaseName    = "home-assistant"
      chart          = "home-assistant"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "home-assistant"
      values = {
        ingress = {
          host = "ha.${var.cluster}.${var.region}.homescale.cloud"
        }
      }
      enabled = var.app_home_assistant_enabled
    },
    {
      releaseName    = "homepage"
      chart          = "homepage"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "homepage"
      values = {
        ingress = {
          host = "homescale.cloud"
        }
      }
      enabled = var.app_homepage_enabled
    },
    {
      releaseName    = "ingress-nginx"
      chart          = "ingress-nginx"
      repoURL        = "https://kubernetes.github.io/ingress-nginx"
      targetRevision = "4.12.1"
      namespace      = "ingress-nginx"
      values = {
        controller = {
          metrics = {
            enabled = true
            serviceMonitor = {
              enabled = true
            }
          }
          service = {
            type              = "LoadBalancer"
            loadBalancerClass = "tailscale"
            annotations = {
              "tailscale.com/hostname" = "ingress-${var.cluster}-${var.region}"
              "tailscale.com/tags"     = "tag:app,tag:region-${var.region},tag:cluster-${var.cluster}"
            }
          }
          autoscaling = {
            enabled     = true
            minReplicas = 1
            maxReplicas = 5
          }
          ingressClassResource = {
            default = true
          }
          extraArgs = {
            "enable-ssl-passthrough" = true
          }
        }
      }
      enabled = var.app_ingress_nginx_enabled
    },
    {
      releaseName    = "librespeed"
      chart          = "librespeed"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "librespeed"
      values = {
        ingress = {
          host = "librespeed.${var.cluster}.${var.region}.homescale.cloud"
        }
      }
      enabled = var.app_librespeed_enabled
    },
    {
      releaseName    = "metrics"
      chart          = "metrics"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "metrics"
      values = {
        kube-prometheus-stack = {
          grafana = {
            "grafana.ini" = {
              server = {
                root_url = "https://metrics.${var.cluster}.${var.region}.homescale.cloud"
              }
              auth = {
                generic_oauth = {
                  client_id     = data.onepassword_item.grafana_oidc.credential
                  client_secret = data.onepassword_item.grafana_oidc.password
                }
              }
            }
            ingress = {
              enabled = true
              hosts   = ["metrics.${var.cluster}.${var.region}.homescale.cloud"]
              tls = [
                {
                  hosts = ["metrics.${var.cluster}.${var.region}.homescale.cloud"]
                }
              ]
            }
          }
        }
      }
      enabled         = var.app_metrics_enabled
      serverSideApply = true
    },
    {
      releaseName    = "node-feature-discovery"
      chart          = "node-feature-discovery"
      repoURL        = "https://kubernetes-sigs.github.io/node-feature-discovery/charts"
      targetRevision = "0.17.3"
      namespace      = "kube-system"
      enabled        = var.app_node_feature_discovery_enabled
    },
    {
      releaseName    = "nfs-provisioner"
      chart          = "nfs-subdir-external-provisioner"
      repoURL        = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
      targetRevision = "4.0.18"
      namespace      = "nfs-provisioner"
      values = {
        nfs = {
          server = var.nfs_server
          path   = var.nfs_path
        }
        storageClass = {
          defaultClass = true
        }
      }
      enabled = var.app_nfs_provisioner_enabled
    },
    {
      releaseName    = "onepassword"
      chart          = "connect"
      repoURL        = "https://1password.github.io/connect-helm-charts/"
      targetRevision = "2.0.2"
      namespace      = "onepassword"
      values = {
        connect = {
          serviceType     = "ClusterIP"
          credentialsName = "onepassword"
          credentialsKey  = "credential"
        }
        operator = {
          create = true
          token = {
            name = "onepassword"
            key  = "password"
          }
        }
      }
      enabled = var.app_onepassword_enabled
    },
    {
      releaseName    = "rbac"
      chart          = "rbac"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "rbac"
      enabled        = var.app_rbac_enabled
    },
    {
      releaseName    = "rook-ceph"
      chart          = "rook-ceph"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "rook-ceph"
      enabled        = var.app_rook_ceph_enabled
    },
    {
      releaseName    = "tailscale"
      chart          = "tailscale-operator"
      repoURL        = "https://pkgs.tailscale.com/helmcharts"
      targetRevision = "1.86.2"
      namespace      = "tailscale"
      values = {
        apiServerProxyConfig = {
          mode = "true"
        }
        proxyConfig = {
          defaultTags = "tag:app,tag:region-${var.region},tag:cluster-${var.cluster}"
        }
        operatorConfig = {
          hostname = "k8s-${var.cluster}-${var.region}"
          defaultTags = [
            "tag:k8s",
            "tag:region-${var.region}",
            "tag:cluster-${var.cluster}"
          ]
        }
      }
      enabled = var.app_tailscale_enabled
    },
    {
      releaseName    = "trivy-operator"
      chart          = "trivy-operator"
      repoURL        = "https://aquasecurity.github.io/helm-charts/"
      targetRevision = "0.29.3"
      namespace      = "trivy-system"
      values = {
        trivy = {
          ignoreUnfixed = true
        }
        service = {
          headless = false
        }
        serviceMonitor = {
          enabled = true
        }
      }
      enabled = var.app_trivy_operator_enabled
    }
  ]
  apps = [for a in local.apps_all : a if(!var.init_stage_1 && !var.init_stage_2) && a.enabled]
}

resource "kubernetes_manifest" "argocd_app" {
  for_each   = { for a in local.apps : a.releaseName => a }
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.value.releaseName
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = each.value.repoURL
        chart          = each.value.chart
        targetRevision = each.value.targetRevision
        helm = merge(
          { releaseName = each.value.releaseName },
          lookup(each.value, "values", null) != null
          ? { valuesObject = each.value.values }
          : {}
        )
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = each.value.namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          lookup(each.value, "serverSideApply", false) ? "ServerSideApply=true" : ""
        ]
      }
    }
  }
}
