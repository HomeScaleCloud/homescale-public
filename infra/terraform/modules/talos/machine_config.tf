locals {
  # No load balancer/VIP in front of the control plane — the first control
  # plane node's own IP is used as this cluster's endpoint. Fine for a
  # single-CP cluster (development today); a multi-CP cluster (production
  # today, 3 CP nodes) that loses this specific node loses its endpoint even
  # though etcd/the rest of the control plane is still healthy. Omni's
  # equivalent (useEmbeddedDiscoveryService) sidestepped this entirely via
  # its own discovery service. Judgment call, flagged in the PR report —
  # revisit with a kube-vip/VIP machine patch if this matters in practice.
  cluster_endpoint = "https://${var.control_plane_nodes[0].ip}:${var.cluster_endpoint_port}"

  # Shared patches (infra/talos/patches/*.yaml) are templatefile'd, not
  # file'd, so base.yaml's ${CLUSTER_NAME} placeholder (previously substituted
  # by CI's envsubst before an `omnictl cluster template sync`) still resolves
  # — now to this module's own var.cluster_name instead.
  shared_patches = [
    for f in var.patch_files :
    templatefile("${path.module}/../../../talos/patches/${f}", { CLUSTER_NAME = var.cluster_name })
  ]

  install_patch = yamlencode({
    machine = {
      install = {
        image = data.talos_image_factory_urls.this.urls.installer
        diskSelector = {
          type = var.install_disk_selector_type
        }
      }
    }
  })

  control_plane_config_patches = concat(
    local.shared_patches,
    [local.install_patch],
    [for p in var.common_extra_patches : yamlencode(p)],
    [for p in var.control_plane_extra_patches : yamlencode(p)],
  )

  worker_config_patches = concat(
    local.shared_patches,
    [local.install_patch],
    [for p in var.common_extra_patches : yamlencode(p)],
    [for p in var.worker_extra_patches : yamlencode(p)],
  )
}

data "talos_machine_configuration" "control_plane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = local.control_plane_config_patches
}

# Only rendered when this cluster actually has worker machines (both
# production and development are control-plane-only today).
data "talos_machine_configuration" "worker" {
  count = length(var.worker_nodes) > 0 ? 1 : 0

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = local.worker_config_patches
}
