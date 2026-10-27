variable "cluster_name" {
  description = "Full Talos cluster identity (e.g. \"production\", \"development\") — used wherever Talos or this provider has a literal cluster-name/cluster-identity field. Never shortened."
  type        = string
}

variable "cluster_name_short" {
  description = "Short identifier for this cluster (e.g. \"prod\", \"dev\") — used only in Infisical secret paths this module creates. Never passed to the Talos provider itself."
  type        = string
}

variable "talos_version" {
  description = "Talos version contract (e.g. \"v1.14.0\") — controls generated machine config schema/defaults, and is used to resolve Image Factory asset URLs. Does not by itself change the installed Talos version; that's driven by the installer image reference baked into machine.install.image (see the image_factory_* resources in schematic.tf)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version baked into the generated machine configuration at bootstrap time."
  type        = string
}

variable "system_extensions" {
  description = "Official Talos system extensions (e.g. [\"siderolabs/iscsi-tools\", \"siderolabs/util-linux-tools\"]) to bake into this cluster's Image Factory schematic/installer image."
  type        = list(string)
  default     = []
}

variable "install_disk_selector_type" {
  description = "Talos disk selector `type` used to pick the install disk on every machine in this cluster (see https://www.talos.dev/latest/reference/configuration/block/diskselector/)."
  type        = string
  default     = "nvme"
}

variable "cluster_endpoint_port" {
  description = "kube-apiserver port used to build this cluster's endpoint URL."
  type        = number
  default     = 6443
}

variable "patch_files" {
  description = "Filenames under infra/talos/patches/ (shared Talos machine config patches) applied, in order, to every machine in this cluster."
  type        = list(string)
  default     = []
}

variable "common_extra_patches" {
  description = "Additional inline config patches (HCL maps; yamlencode'd internally) applied to every machine regardless of role in this cluster only — for anything hardware-specific that doesn't belong in the shared infra/talos/patches/ files and isn't the network/address config (that's `network_interface` below, since it has to be generated per-machine, not shared)."
  type        = list(any)
  default     = []
}

variable "network_interface" {
  description = <<-EOT
    Shared network interface shape (interface name, bond config, VLANs — everything
    except addressing) applied to every machine in this cluster. This module layers
    in each machine's own static address (from its `ip`, plus `network_prefix_length`)
    on top of this shape, per machine, via `talos_machine_configuration_apply`'s own
    `config_patches` — it can't be folded into `common_extra_patches` because every
    machine's generated patch needs a different address. Set to `null` to skip adding
    any network patch at all (e.g. if DHCP reservations are used instead of static
    addressing, in which case plain DHCP from `infra/talos/patches/` or elsewhere is
    enough and this module adds nothing of its own).
  EOT
  type        = any
  default     = null
}

variable "network_prefix_length" {
  description = "CIDR prefix length for each machine's static address on `network_interface` (e.g. 24 for a /24). Unused if `network_interface` is null."
  type        = number
  default     = 24
}

variable "control_plane_extra_patches" {
  description = "Additional inline config patches applied only to control plane machines in this cluster (e.g. scheduler topology spread)."
  type        = list(any)
  default     = []
}

variable "worker_extra_patches" {
  description = "Additional inline config patches applied only to worker machines in this cluster."
  type        = list(any)
  default     = []
}

variable "control_plane_nodes" {
  description = <<-EOT
    Control plane machines for this cluster.

    `ip` is the machine's permanent, intended static address — it's what gets baked
    into the generated static-addressing config patch (see `network_interface`), and
    what every *steady-state* Terraform operation (health checks, kubeconfig fetch,
    future config updates) always targets. It must be routable from wherever
    Terraform runs (CI, or local) — directly, or via the Tailscale subnet router onto
    the Talos nodes' own LAN.

    `bootstrap_ip` handles the chicken-and-egg first-boot problem: a brand new
    machine comes up on DHCP, with no static address yet — that only takes effect
    once this module's own generated config (which sets it) has actually been
    delivered. So the *very first* `talos_machine_configuration_apply`/
    `talos_machine_bootstrap` call for a machine has to dial its current DHCP
    address instead of `ip`. Set `bootstrap_ip` to that machine's DHCP-assigned
    address (found by hand — e.g. the router/DHCP lease table, or read directly off
    the Talos maintenance-mode console) for its first-ever apply only; leave it unset
    (`null`) for every machine that's already on its static address. Once an apply
    with `bootstrap_ip` set succeeds and you've confirmed the machine now answers at
    `ip` instead (`talosctl -e <ip> -n <ip> version`, or similar), remove
    `bootstrap_ip` from that machine's entry — this is a one-time, by-hand step per
    machine, not something this module automates (see CLAUDE.md's Clusters section
    and docs/operations/registering-machines.md).

    The first entry's `ip` is used as this cluster's kube-apiserver/Talos endpoint
    (no load balancer/VIP is configured — see the module README note in the root
    talos-*.tf files for the HA caveat this implies).
  EOT
  type = list(object({
    name         = string
    ip           = string
    bootstrap_ip = optional(string)
  }))
}

variable "worker_nodes" {
  description = "Worker machines for this cluster. Empty for a control-plane-only cluster (the current shape of both production and development). Same `ip`/`bootstrap_ip` split as `control_plane_nodes` — see there."
  type = list(object({
    name         = string
    ip           = string
    bootstrap_ip = optional(string)
  }))
  default = []
}

variable "infisical_workspace_id" {
  description = "Infisical project/workspace UUID, for storing this cluster's break-glass admin kubeconfig."
  type        = string
}
