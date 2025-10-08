resource "talos_machine_secrets" "controlplane" {}

data "talos_client_configuration" "controlplane" {
  cluster_name         = var.cluster
  client_configuration = talos_machine_secrets.controlplane.client_configuration
  nodes                = var.controlplane_nodes
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.vip}:6443"
  talos_version    = "1.11.2"
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
    yamlencode({
      machine = {
        nodeLabels = {
            "cluster.homescale.cloud/name" = var.cluster
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
                ip = var.vip
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
  node                 = var.vip
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