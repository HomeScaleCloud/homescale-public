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

      filename = "99_netbird.yaml"

      contents = <<-YAML
        stages:
          network:
            - name: install and connect NetBird
              commands:
                - if ! command -v netbird >/dev/null 2>&1; then   curl -L -o ./netbird_0.70.5.tar.gz https://github.com/netbirdio/netbird/releases/download/v0.70.5/netbird_0.70.5_linux_amd64.tar.gz; tar xzf ./netbird_0.70.5.tar.gz; mv netbird /root/bin/netbird; chmod +x /root/bin/netbird; /root/bin/netbird service install; fi
                - /root/bin/netbird service start || true
                - netbird status 2>/dev/null | grep -qi connected || netbird up --allow-server-ssh --enable-ssh-local-port-forwarding --enable-ssh-remote-port-forwarding --enable-ssh-sftp --setup-key '${var.netbird_setup_key}'
                - netbird status || true
      YAML
      paused   = false
    }
  }

  field_manager {
    force_conflicts = true
  }
}
