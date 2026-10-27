# Bootstraps etcd on the first control plane node only, once — this is a
# one-time cluster-lifecycle action (it panics on an already-bootstrapped
# node), not something to re-run as config changes. Mirrors Omni's own
# one-shot cluster bootstrap.
#
# Targets the same address apply.tf just used for this node (its bootstrap_ip
# if that's still set, otherwise its static ip) — see the control_plane_nodes
# variable for why. The first ever run against a brand new cluster therefore
# bootstraps over the DHCP address too; by the time this is called,
# talos_machine_configuration_apply has already delivered the static-address
# config, so a subsequent terraform apply (once the operator confirms the
# node answers at its static ip and clears bootstrap_ip) is what actually
# moves this resource's target over, same as every other node reference here.
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.control_plane]

  node                 = local.node_apply_target[var.control_plane_nodes[0].name]
  client_configuration = talos_machine_secrets.this.client_configuration
}
