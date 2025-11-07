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
      enabled        = var.app_cert_manager_enabled
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
      enabled        = var.app_external_dns_enabled
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
          host = "ha-${var.cluster}.${var.tailscale_tailnet}"
          annotations = {
            "tailscale.com/hostname" = "ha-${var.cluster}"
            "tailscale.com/tags"     = "tag:app-ha,tag:cluster-${var.cluster},tag:region-${var.region}"
          }
        }
        zigbee = {
          local      = true
          devicePath = "/dev/ttyUSB0"
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
              "tailscale.com/hostname" = "ingress-${var.cluster}"
              "tailscale.com/tags"     = "tag:app,tag:cluster-${var.cluster},tag:region-${var.region}"
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
          host = "librespeed-${var.cluster}.${var.tailscale_tailnet}"
          annotations = {
            "tailscale.com/hostname" = "librespeed-${var.cluster}"
            "tailscale.com/tags"     = "tag:app,tag:cluster-${var.cluster},tag:region-${var.region}"
          }
        }
      }
      enabled = var.app_librespeed_enabled
    },
    {
      releaseName    = "metrics"
      chart          = "kube-prometheus-stack"
      repoURL        = "https://prometheus-community.github.io/helm-charts"
      targetRevision = "78.3.0"
      namespace      = "metrics"
      values = {
        grafana = {
          defaultDashboardsEnabled = false
          service = {
            type = "ClusterIP"
          }
          "grafana.ini" = {
            server = {
              root_url = "https://metrics-${var.cluster}.${var.tailscale_tailnet}"
            }
            auth = {
              disable_login_form = true
            }
            "auth.generic_oauth" = {
              enabled                    = true
              name                       = "Entra ID"
              allow_sign_up              = true
              auto_login                 = false
              client_id                  = data.onepassword_item.grafana_oidc.credential
              client_secret              = data.onepassword_item.grafana_oidc.password # pragma: allowlist secret
              scopes                     = "openid email profile offline_access User.Read"
              auth_url                   = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/authorize"
              token_url                  = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/token"
              role_attribute_path        = "\"Admin\""
              role_attribute_strict      = false
              allow_assign_grafana_admin = true
            }
            users = {
              auto_assign_org      = true
              auto_assign_org_role = "Admin"
              allow_sign_up        = false
            }
          }
          persistence = {
            enabled     = true
            type        = "pvc"
            accessModes = ["ReadWriteOnce"]
            size        = "5Gi"
          }
          ingress = {
            enabled          = true
            ingressClassName = "tailscale"
            annotations = {
              "tailscale.com/hostname"    = "metrics-${var.cluster}"
              "tailscale.com/tags"        = "tag:app-metrics,tag:cluster-${var.cluster},tag:region-${var.region}"
              "tailscale.com/proxy-group" = "ingress"
            }
            hosts = ["metrics-${var.cluster}.${var.tailscale_tailnet}"]
            tls = [
              {
                hosts = ["metrics-${var.cluster}.${var.tailscale_tailnet}"]
              }
            ]
          }
          assertNoLeakedSecrets = false
          dashboardProviders = {
            "dashboardproviders.yaml" = {
              apiVersion = 1
              providers = [
                {
                  name            = "grafana-dashboards"
                  orgId           = 1
                  folder          = ""
                  type            = "file"
                  disableDeletion = true
                  editable        = true
                  options = {
                    path = "/var/lib/grafana/dashboards/grafana-dashboards"
                  }
                }
              ]
            }
          }
          dashboards = {
            "grafana-dashboards" = {
              "k8s-system-api-server" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-api-server.json"
                token = ""
              }
              "k8s-addons-prometheus" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-addons-prometheus.json"
                token = ""
              }
              "k8s-system-coredns" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-coredns.json"
                token = ""
              }
              "k8s-views-global" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-global.json"
                token = ""
              }
              "k8s-views-namespaces" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-namespaces.json"
                token = ""
              }
              "k8s-views-nodes" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-nodes.json"
                token = ""
              }
              "k8s-views-pods" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-pods.json"
                token = ""
              }
              "k8s-events-exporter" = {
                url   = "https://grafana.com/api/dashboards/17882/revisions/2/download"
                token = ""
              }
              "ingress-controller" = {
                url        = "https://grafana.com/api/dashboards/9614/revisions/1/download"
                token      = ""
                datasource = "Prometheus"
              }
              "k8s-addons-trivy-operator" = {
                url   = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-addons-trivy-operator.json"
                token = ""
              }
              "node-exporter-full" = {
                url   = "https://grafana.com/api/dashboards/1860/revisions/41/download"
                token = ""
              }
              "argocd-overview" = {
                url   = "https://grafana.com/api/dashboards/14584/revisions/1/download"
                token = ""
              }
            }
          }
        }
        prometheus = {
          annotations = {
            "argocd.argoproj.io/skip-health-check" = "true"
          }
          prometheusSpec = {
            podMonitorSelectorNilUsesHelmValues     = false
            serviceMonitorSelectorNilUsesHelmValues = false
            serviceMonitorSelector                  = {}
            serviceMonitorNamespaceSelector         = {}
            storageSpec = {
              volumeClaimTemplate = {
                spec = {
                  accessModes = ["ReadWriteOnce"]
                  resources = {
                    requests = {
                      storage = "50Gi"
                    }
                  }
                }
              }
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
      repoURL        = "https://charts.rook.io/release"
      targetRevision = "v1.18.4"
      namespace      = "rook-ceph"
      values = {
        monitoring = {
          enabled = true
        }
      }
      enabled = var.app_rook_ceph_enabled
    },
    {
      releaseName    = "rook-ceph-cluster"
      chart          = "rook-ceph-cluster"
      repoURL        = "https://charts.rook.io/release"
      targetRevision = "v1.18.4"
      namespace      = "rook-ceph"
      values = {
        monitoring = {
          enabled               = true
          createPrometheusRules = true
        }
        cephClusterSpec = {
          mgr = {
            modules = [
              {
                name    = "rook"
                enabled = true
              }
            ]
          }
          storage = {
            useAllNodes   = true
            useAllDevices = true
          }
        }
      }
      enabled = var.app_rook_ceph_enabled
    },
    {
      releaseName    = "tailscale"
      chart          = "tailscale-operator"
      repoURL        = "https://pkgs.tailscale.com/helmcharts"
      targetRevision = "1.86.2"
      namespace      = "tailscale"
      values = {
        apiServerProxyConfig = {
          allowImpersonation = "true"
        }
        proxyConfig = {
          defaultTags = "tag:app,tag:cluster-${var.cluster},tag:region-${var.region}"
        }
        operatorConfig = {
          hostname = "ts-operator-${var.cluster}"
          defaultTags = [
            "tag:k8s",
            "tag:cluster-${var.cluster}",
            "tag:region-${var.region}"
          ]
        }
      }
      enabled = var.app_tailscale_enabled
    },
    {
      releaseName    = "tailscale-crs"
      chart          = "tailscale-crs"
      repoURL        = "ghcr.io/homescalecloud/helm"
      targetRevision = "0.1.0"
      namespace      = "tailscale"
      values = {
        cluster = {
          name   = var.cluster
          region = var.region
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
