# Registering New Machines

Add machines to `clusters/<cluster>/topf.yaml`. TOPF generates Talos configuration; Terraform manages external services.

## Installation media

Reuse the cluster's schematicId and talosVersion. Download matching media from `https://factory.talos.dev/image/<schematic-id>/v<talos-version>/metal-<arch>-secureboot.iso`. Write it to USB or mount it through the server's BMC.

Enable UEFI SecureBoot. Where required, enroll the image's SecureBoot keys from the boot menu while firmware is in setup mode. Boot into maintenance mode, record its DHCP address and verify:

```bash
talosctl --nodes <dhcp-ip> get securitystate --insecure
talosctl --nodes <dhcp-ip> get disks --insecure
```

Confirm the actual installation disk, NIC names, permanent address, DNS and gateway before editing inventory. Do not infer them from another machine.

## First cluster

Complete the permanent inventory and run the LAN bootstrap with a nodes.yaml listing every control-plane node. Follow [Clusters: bootstrap](../architecture/clusters.md#bootstrap-adding-a-new-cluster). The DHCP address is only the initial apply target; authenticated bootstrap uses the permanent address.

## Additional nodes

Add a unique host alias, permanent ip and role to topf.yaml. The alias names the rendered file; Talos generates its own stable hostname. Cluster-wide disk and network settings apply automatically; put a verified installDiskMatch override in the node data only if its disk differs. Shared role and network patches apply automatically.

From the LAN, render into a private temporary directory and apply only the new node's file:

```bash
umask 077
workspace=$(mktemp -d)
hsctl run topf --cluster production render --output "$workspace/configs"
talosctl --nodes <dhcp-ip> apply-config --insecure --file "$workspace/configs/<alias>.yaml"
rm -rf "$workspace"
```

Clean up the workspace even if apply fails. Rendered files contain credentials; never commit them. Once the node answers at its permanent address, preview future changes with `hsctl run topf --cluster production --nodes-filter '^alias$' apply --dry-run`. Existing cluster credentials are reused. Do not initialize a new CA or bootstrap etcd again.

CI reaches existing clusters through their Tailscale subnet routers. Keep a new cluster's data.bootstrapComplete false until local bootstrap, ArgoCD sync and remote connectivity have succeeded.
