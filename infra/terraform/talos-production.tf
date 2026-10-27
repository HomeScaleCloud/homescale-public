# The "production" Talos/Kubernetes cluster (formerly boa1-prod / Omni-
# managed). Replaces clusters/production/cluster.yaml (deleted) — machine
# inventory, patches, versions, and system extensions now all live here
# instead of an Omni cluster template.
module "talos_production" {
  source = "./modules/talos"

  cluster_name       = "production"
  cluster_name_short = "prod"

  talos_version      = "v1.14.0"
  kubernetes_version = "v1.37.0"

  system_extensions = [
    "siderolabs/iscsi-tools",
    "siderolabs/util-linux-tools",
  ]

  patch_files = [
    "base.yaml",
    "longhorn.yaml",
    "kubelet-certs.yaml",
  ]

  # Hardware-specific network shape, carried over as-is from the old
  # clusters/production/cluster.yaml ControlPlane `nics` patch — everything
  # except addressing, which the module generates per machine from each
  # entry's own `ip` below (static, not DHCP — see control_plane_nodes).
  network_interface = {
    interface = "bond0"
    bond = {
      mode           = "802.3ad"
      lacpRate       = "fast"
      xmitHashPolicy = "layer3+4"
      miimon         = 100
      interfaces     = ["eno1", "eno2", "eno3", "eno4"]
    }
    vlans = [
      { vlanId = 241 },
      { vlanId = 271 },
    ]
  }
  # network_prefix_length defaults to 24, matching these /24 addresses.

  control_plane_extra_patches = [
    {
      apiVersion = "v1alpha1"
      kind       = "KubeSchedulerConfig"
      config = {
        profiles = [
          {
            schedulerName = "default-scheduler"
            pluginConfig = [
              {
                name = "PodTopologySpread"
                args = {
                  defaultConstraints = [
                    {
                      maxSkew           = 1
                      topologyKey       = "kubernetes.io/hostname"
                      whenUnsatisfiable = "ScheduleAnyway"
                    }
                  ]
                  defaultingType = "List"
                }
              }
            ]
          }
        ]
      }
    }
  ]

  # bootstrap_ip is left unset here because each machine's real DHCP address
  # isn't known until it's actually reimaged and booted — this cluster is a
  # from-scratch rebuild of the physical machines previously running as
  # Omni-managed boa1-prod (reimaged via this module's own Image Factory
  # schematic, not adopted in place), with data continuity handled by VolSync
  # restores (see clusters/production/apps.yaml's home-assistant
  # volsync.restore.sourceCluster override), not by preserving these nodes'
  # existing state. For each machine's first-ever apply: reimage it (see
  # docs/operations/registering-machines.md), boot it, read its DHCP address
  # off the console/router, set that machine's `bootstrap_ip` here temporarily,
  # apply, confirm it now answers at its static `ip`, then remove
  # `bootstrap_ip` again — see the control_plane_nodes variable in
  # modules/talos/variables.tf for the full procedure.
  control_plane_nodes = [
    { name = "production-cp-1", ip = "10.1.245.21" },
    { name = "production-cp-2", ip = "10.1.245.22" },
    { name = "production-cp-3", ip = "10.1.245.23" },
  ]

  # No worker machines today — all 3 physical machines are control plane
  # (matches the old cluster.yaml, which had no separate Worker machine set).
  worker_nodes = []

  infisical_workspace_id = module.infisical.project_id
}
