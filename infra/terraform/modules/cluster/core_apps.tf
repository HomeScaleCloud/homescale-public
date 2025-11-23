resource "helm_release" "cilium" {
  count = var.init_stage_1 ? 0 : 1
  depends_on = [
    talos_machine_bootstrap.controlplane
  ]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.18.4"
  namespace  = "kube-system"

  values = [
    yamlencode({
      operator = {
        replicas = 1
      }
      socketLB = {
        hostNamespaceOnly = true
      }
      bpf = {
        lbExternalClusterIP = true
      }
      ipam = {
        mode = "kubernetes"
      }
      kubeProxyReplacement = true
      securityContext = {
        capabilities = {
          ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
          cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
        }
      }
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }
      k8sServiceHost = "localhost"
      k8sServicePort = 7445
      extraArgs = [
        "--devices=${var.mgmt_interface}"
      ]
    })
  ]
}

resource "helm_release" "argocd" {
  count = var.init_stage_1 ? 0 : 1
  depends_on = [
    helm_release.cilium
  ]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.1.4"
  namespace        = "argocd"
  create_namespace = true

  values = [
    yamlencode({
      global = {
        domain = "argocd-${var.cluster}.${var.tailscale_tailnet}"
      }

      certificate = {
        enabled = true
      }

      repoServer = {
        extraArgs = ["--repo-cache-expiration=30m"]
      }

      server = {
        ingress = {
          enabled          = true
          ingressClassName = "tailscale"
          annotations = {
            "tailscale.com/hostname"    = "argocd-${var.cluster}"
            "tailscale.com/tags"        = "tag:app-argocd,tag:cluster-${var.cluster},tag:region-${var.region}"
            "tailscale.com/proxy-group" = "ingress"
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
                    - team-infra-plat
                    - sec-infra-plat-pim
          YAML
          "admin.enabled"                  = false
          "statusbadge.enabled"            = true
          "server.rbac.log.enforce.enable" = "true"
          "timeout.reconciliation"         = "45s"
        }

        rbac = {
          "policy.csv" = <<-CSV
            g, sec-infra-plat-pim, role:admin
            p, role:argo-users, applications, get, *, allow
            p, role:argo-users, applications, refresh, *, allow
            p, role:argo-users, applications, sync, *, allow
            p, role:argo-users, projects, get, *, allow
            p, role:argo-users, repositories, get, *, allow
            p, role:argo-users, clusters, get, *, allow
            p, role:argo-users, accounts, get, *, allow
            p, role:argo-users, logs, get, *, deny
            p, role:argo-users, logs, get, */*, deny
            g, team-infra-plat, role:argo-users
          CSV
        }
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

resource "kubernetes_secret" "argocd_homescale_helm" {
  count      = var.init_stage_1 ? 0 : 1
  depends_on = [helm_release.argocd]
  metadata {
    name      = "argocd-homescale-helm"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    url       = "ghcr.io/homescalecloud/helm"
    name      = "homescale-helm"
    type      = "helm"
    enableOCI = "true"
  }
}
