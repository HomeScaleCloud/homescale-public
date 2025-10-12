resource "helm_release" "cilium" {
  count = var.cluster_init ? 0 : 1
  depends_on = [
    talos_machine_bootstrap.controlplane
  ]
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.18.2"
  namespace  = "kube-system"

  set = [
    {
      name  = "ipam.mode"
      value = "kubernetes"
    },
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "securityContext.capabilities.ciliumAgent"
      value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
    },
    {
      name  = "securityContext.capabilities.cleanCiliumState"
      value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
    },
    {
      name  = "cgroup.autoMount.enabled"
      value = "false"
    },
    {
      name  = "cgroup.hostRoot"
      value = "/sys/fs/cgroup"
    },
    {
      name  = "k8sServiceHost"
      value = "localhost"
    },
    {
      name  = "k8sServicePort"
      value = "7445"
    }
  ]
}

resource "helm_release" "argocd" {
  count = var.cluster_init ? 0 : 1
  depends_on = [
    helm_release.cilium
  ]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.3.3"
  namespace        = "argocd"
  create_namespace = true

  values = [
    yamlencode({
      global = {
        domain = "argocd.${var.cluster}.${var.region}.homescale.cloud"
      }

      certificate = {
        enabled = true
      }

      server = {
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          annotations = {
            "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
            "nginx.ingress.kubernetes.io/ssl-passthrough"    = "true"
            "cert-manager.io/cluster-issuer"                 = "letsencrypt"
          }
          tls = true
        }
      }

      configs = {
        cm = {
          "dex.config"                     = <<-YAML
            connectors:
              - type: microsoft
                id: microsoft
                name: Entra ID
                config:
                  clientID: ${data.onepassword_item.argocd_oidc.username}
                  clientSecret: ${data.onepassword_item.argocd_oidc.password}
                  tenant: ${data.onepassword_item.entra_tenant.credential}
                  groups:
                    - team-k8s-infra
                    - sg-k8s-infra-admin
          YAML
          "admin.enabled"                  = false
          "statusbadge.enabled"            = true
          "server.rbac.log.enforce.enable" = "true"
          "timeout.reconciliation"         = "45s"
        }
      }

      rbac = {
        "policy.csv" = <<-CSV
          g, sg-k8s-infra-admin, role:admin
          p, role:argo-users, applications, get, *, allow
          p, role:argo-users, applications, refresh, *, allow
          p, role:argo-users, applications, sync, *, allow
          p, role:argo-users, projects, get, *, allow
          p, role:argo-users, repositories, get, *, allow
          p, role:argo-users, clusters, get, *, allow
          p, role:argo-users, accounts, get, *, allow
          p, role:argo-users, logs, get, *, deny
          p, role:argo-users, logs, get, */*, deny
          g, team-k8s-infra, role:argo-users
        CSV
      }

      notifications = {
        subscriptions = <<-YAML
          - recipients:
              - slack:argocd
            triggers:
              - on-update-failed
        YAML

        templates = {
          "template.app-update-failed" = <<-YAML
            slack:
              attachments: |
                [{
                  "title": "{{ .app.metadata.name}}",
                  "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
                  "color": "#E96D76",
                  "fields": [
                    { "title": "Sync Status", "value": "Failed", "short": true },
                    { "title": "Finished At", "value": "{{.app.status.operationState.finishedAt}}", "short": true },
                    { "title": "Error", "value": "{{.app.status.operationState.message}}", "short": true }
                  ]
                }]
          YAML
        }

        triggers = {
          "trigger.on-update-failed" = <<-YAML
            - description: Application update has failed
              send:
                - app-update-failed
              when: app.status.operationState.phase in ['Failed', 'Error', 'Unknown']
          YAML
        }
      }
    })
  ]
}

resource "kubernetes_manifest" "argocd_homescale_helm" {
  count      = var.cluster_init ? 0 : 1
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "argocd-homescale-helm"
      namespace = "argocd"
      labels = {
        "argocd.argoproj.io/secret-type" = "repository"
      }
    }
    stringData = {
      url       = "ghcr.io/homescalecloud/helm"
      name      = "homescale-helm"
      type      = "helm"
      enableOCI = "true"
    }
  }
}