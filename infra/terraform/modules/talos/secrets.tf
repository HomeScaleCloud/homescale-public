# Generates and holds this cluster's Talos cluster secrets (CA material,
# bootstrap token, etc.) directly in Terraform state (Terraform Cloud) — the
# siderolabs/talos provider needs no external credential/API token of its own
# beyond this; it talks to each node's apid directly over TCP:50000 using the
# client certificate generated here.
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}
