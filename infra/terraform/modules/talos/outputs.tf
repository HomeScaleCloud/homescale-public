output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "schematic_id" {
  description = "Image Factory schematic ID for this cluster — pass the same system_extensions when building installation media by hand so a freshly registered machine's media matches what's already running."
  value       = talos_image_factory_schematic.this.id
}

output "installer_image" {
  value = data.talos_image_factory_urls.this.urls.installer
}

output "iso_url" {
  description = "Image Factory ISO download URL for onboarding a new machine (see docs/operations/registering-machines.md)."
  value       = data.talos_image_factory_urls.this.urls.iso
}
