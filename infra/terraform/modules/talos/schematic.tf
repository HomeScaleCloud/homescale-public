# Replaces Omni's "Download Installation Media" schematic wizard: this
# cluster's system extensions are baked into an Image Factory schematic here,
# and the resulting installer image reference is injected into every
# machine's config (see the install_patch local in machine_config.tf) via
# machine.install.image, so a Talos upgrade also picks up extension changes.
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.system_extensions
      }
    }
  })
}

# Resolves installer/ISO/etc. URLs for this schematic + Talos version. "iso"
# is what a human downloads to write to a USB drive/mount as BMC virtual
# media when onboarding a new machine (see docs/operations/registering-machines.md)
# — Terraform itself never downloads or writes it, it only computes the URL.
data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
}
