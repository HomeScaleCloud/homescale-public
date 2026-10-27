# The "development" Talos/Kubernetes cluster (formerly boa1-lab / Omni-
# managed). Replaces clusters/development/cluster.yaml (deleted). See
# talos-production.tf for the general shape/comments — not repeated here.
module "talos_development" {
  source = "./modules/talos"

  cluster_name       = "development"
  cluster_name_short = "dev"

  talos_version      = "v1.14.0"
  kubernetes_version = "v1.37.0"

  # No system extensions on this cluster today (no Longhorn here, unlike
  # production — matches the old cluster.yaml, which had no systemExtensions
  # key at all for boa1-lab).
  system_extensions = []

  patch_files = [
    "base.yaml",
    "kubelet-certs.yaml",
  ]

  # Hardware-specific network shape, carried over as-is from the old
  # clusters/development/cluster.yaml ControlPlane `nics` patch — everything
  # except addressing, which the module generates from `ip` below (static,
  # not DHCP — no bonding on this single-node cluster, but still a single
  # interface that needs an address).
  network_interface = {
    interface = "bond0"
    bond = {
      mode           = "802.3ad"
      lacpRate       = "fast"
      xmitHashPolicy = "layer3+4"
      miimon         = 100
      interfaces     = ["eno1", "eno2"]
    }
    vlans = [
      { vlanId = 241 },
      { vlanId = 271 },
    ]
  }
  # network_prefix_length defaults to 24, matching this /24 address.

  # bootstrap_ip left unset for the same reason as talos-production.tf: this
  # single machine's real DHCP address isn't known until it's actually
  # reimaged and booted. There's no VolSync backup to restore for this
  # cluster (boa1-lab had none — only production's apps did), so this one is
  # a genuinely clean rebuild with no data-continuity step needed.
  control_plane_nodes = [
    { name = "development-cp-1", ip = "10.1.245.30" },
  ]

  worker_nodes = []

  infisical_workspace_id = module.infisical.project_id
}
