locals {
  control_plane_by_name = { for n in var.control_plane_nodes : n.name => n }
  worker_by_name        = { for n in var.worker_nodes : n.name => n }
  all_nodes_by_name     = merge(local.control_plane_by_name, local.worker_by_name)

  # Each machine's own static-addressing patch, layered on top of the shared
  # role-wide generated config at apply time (same mechanism the provider's own
  # docs use to layer an install-disk patch on top of a generated config) — see
  # the `network_interface` variable for why this can't just be another entry in
  # `common_extra_patches`. Keyed by machine name; empty map (and so no patch) if
  # `network_interface` is null.
  node_network_patches = var.network_interface == null ? {} : {
    for key, n in local.all_nodes_by_name :
    key => yamlencode({
      machine = {
        network = {
          interfaces = [
            merge(var.network_interface, {
              dhcp      = false
              addresses = ["${n.ip}/${var.network_prefix_length}"]
            })
          ]
        }
      }
    })
  }

  # Chicken-and-egg first boot: a machine with `bootstrap_ip` set hasn't yet
  # received (or hasn't yet confirmed-applied) the static-addressing config this
  # module generates, so it must still be dialed on its current DHCP address
  # instead of its intended static `ip`. See the `control_plane_nodes` variable
  # for the full by-hand bootstrap procedure this supports.
  node_apply_target = { for key, n in local.all_nodes_by_name : key => coalesce(n.bootstrap_ip, n.ip) }
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each = local.control_plane_by_name

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  config_patches              = var.network_interface == null ? null : [local.node_network_patches[each.key]]
  node                        = local.node_apply_target[each.key]
  endpoint                    = local.node_apply_target[each.key]
  apply_mode                  = "staged_if_needing_reboot"
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_by_name

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[0].machine_configuration
  config_patches              = var.network_interface == null ? null : [local.node_network_patches[each.key]]
  node                        = local.node_apply_target[each.key]
  endpoint                    = local.node_apply_target[each.key]
  apply_mode                  = "staged_if_needing_reboot"
}
