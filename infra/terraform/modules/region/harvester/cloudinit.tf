resource "kubernetes_manifest" "cloudinit_netbird" {
  manifest = {
    apiVersion = "node.harvesterhci.io/v1beta1"
    kind       = "CloudInit"
    metadata = {
      name = "netbird"
    }
    spec = {
      matchSelector = {
        "harvesterhci.io/managed" = "true"
      }
      filename = "99-netbird.yaml"
      contents = yamlencode({
        stages = {
          network = [
            {
              name = "install and connect NetBird"

              commands = [
                "if ! command -v netbird >/dev/null 2>&1; then curl -fsSL https://pkgs.netbird.io/install.sh | sh; fi",
                "systemctl enable --now netbird || true",
                "netbird status 2>/dev/null | grep -qi connected || netbird up --setup-key '${var.netbird_setup_key}'",
                "netbird status || true"
              ]
            }
          ]
        }
      })
      paused = false
    }
  }
  field_manager {
    force_conflicts = true
  }
}
