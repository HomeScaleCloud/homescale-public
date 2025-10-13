resource "talos_machine_secrets" "controlplane" {}
resource "talos_image_factory_schematic" "image" {
  schematic = yamlencode(
    {
      customization = {
        secureboot = {
          includeWellKnownCertificates = true
        }
      }
    }
  )
}

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
    yamlencode({
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
    yamlencode({
      cluster = {
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml"
        ]
      }
    }),
    var.cluster_init_core_apps ? null : yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
      }
    }),
    yamlencode({
      machine = {
        sysctls = {
          "user.max_user_namespaces" = "10000"
        }
      }
    }),
    yamlencode({
      machine = {
        nodeLabels = {
          "cluster.homescale.cloud/name"     = var.cluster
          "cluster.homescale.cloud/region"   = var.region
          "cluster.homescale.cloud/platform" = var.platform
          "node.homescale.cloud/region"      = var.region
          "node.homescale.cloud/os"          = "talos"
          "node.homescale.cloud/os-version"  = var.talos_version

        }
      }
    }),
    var.workloads_on_controlplane ? yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }) : null,
    yamlencode({
      machine = {
        install = {
          diskSelector = var.talos_disk_selector
          image        = "factory.talos.dev/${var.platform}-installer-secureboot/${talos_image_factory_schematic.image.id}:${var.talos_version}"
        }
      }
    }),
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "eno1"
              dhcp      = false
              addresses = ["${each.value}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
              vip = {
                ip = var.controlplane_vip
              }
            }
          ]
          nameservers = [
            "10.1.245.1",
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