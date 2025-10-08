resource "talos_machine_secrets" "controlplane" {}

data "talos_client_configuration" "controlplane" {
  cluster_name         = var.cluster
  client_configuration = talos_machine_secrets.controlplane.client_configuration
  nodes                = var.controlplane_nodes
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.controlplane_vip}:6443"
  talos_version    = var.talos_version
  machine_secrets  = talos_machine_secrets.controlplane.machine_secrets
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each                    = local.controlplane_nodes
  client_configuration        = talos_machine_secrets.controlplane.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = format("%s-cp-%d", var.cluster, each.key)
        }
      }
    }),
    yamldecode({
      cluster = {
        apiServer = {
          admissionControl = [
            {
              name = "PodSecurity"
              configuration = {
                exemptions = {
                  namespaces = [
                    "rook-ceph",
                    "metrics",
                    "node-feature-discovery",
                    "falco",
                    "tailscale",
                    "trivy-system",
                    "home-assistant",
                  ]
                }
              }
            }
          ]
        }
      }
    }),
    yamldecode({
      cluster = {
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml"
        ]
      }
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
      }
    }),
    yamldecode({
      cluster = {
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml"
        ]
      }
      machine = {
        sysctls = {
          "user.max_user_namespaces" = "10000"
        }
      }
    }),
    yamlencode({
      machine = {
        nodeLabels = {
          "cluster.homescale.cloud/name"    = var.cluster
          "cluster.homescale.cloud/region"  = var.region
          "node.homescale.cloud/region"     = var.region
          "node.homescale.cloud/os"         = "talos"
          "node.homescale.cloud/os-version" = var.talos_version

        }
      }
    }),
    yamlencode({
      machine = {
        install = { diskSelector = { size = 250059350016 } }
      }
    }),
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "eno1"
              dhcp      = true
              vip = {
                ip = var.controlplane_vip
              }
            }
          ]
        }
      }
    }),
    yamlencode({
      cluster = {
        network = { cni = { name = "none" } },
        proxy   = { disabled = true }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "controlplane" {
  depends_on = [
    talos_machine_configuration_apply.controlplane
  ]
  node                 = var.controlplane_nodes[0]
  client_configuration = talos_machine_secrets.controlplane.client_configuration
}

resource "talos_cluster_kubeconfig" "cluster" {
  depends_on = [
    talos_machine_bootstrap.controlplane
  ]
  client_configuration = talos_machine_secrets.controlplane.client_configuration
  node                 = var.controlplane_vip
}

resource "helm_release" "cilium" {
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