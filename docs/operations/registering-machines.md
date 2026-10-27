# Registering New Machines

This page walks through onboarding a new bare-metal machine so Terraform can manage it as part of a cluster. There's no separate "registration"/claim step with an external control plane any more — Terraform owns the machine's config directly once its IP is in the relevant `talos-<cluster>.tf` file.

## 1. Build a schematic and get an ISO

Talos [Image Factory](https://factory.talos.dev) replaces Omni's "Download Installation Media" wizard. Two ways to get there:

**Reuse the cluster's existing schematic (preferred — matches what its other machines already run):**

```bash
terraform -chdir=infra/terraform output -raw module.talos_production.schematic_id
terraform -chdir=infra/terraform output -raw module.talos_production.iso_url
```

(swap `talos_production` for `talos_development` as needed). Download the ISO from the printed URL.

**Or build a schematic by hand**, if you need different system extensions than the cluster currently runs:

```bash
curl -X POST https://factory.talos.dev/schematics \
  -d '{"customization":{"systemExtensions":{"officialExtensions":["siderolabs/iscsi-tools","siderolabs/util-linux-tools"]}}}'
# → {"id": "<schematic-id>", "schematic": "..."}

curl -LO "https://factory.talos.dev/image/<schematic-id>/v1.14.0/metal-amd64.iso"
```

Check the target cluster's `system_extensions` list in `infra/terraform/talos-<cluster>.tf` so the media matches what Terraform will configure the machine with.

!!! note "Secure Boot"
    Image Factory supports Secure Boot assets (`-secureboot` suffixed paths/installer tags). Omni's `OmniSecureBootDisabled` alert (and its runbook) no longer exist — there is currently no equivalent automated check that a machine has Secure Boot enabled if you intend to enforce it. Verify manually if that matters for your hardware.

## 2. Write the ISO to media

**USB drive:**

```bash
# macOS — find the device with `diskutil list`, then:
dd if=<path-to-iso> of=/dev/diskN conv=fdatasync

# Linux — find the device with `lsblk`, then:
dd if=<path-to-iso> of=/dev/sdX conv=fdatasync
```

**Servers with out-of-band management** (iDRAC, iLO, IPMI): mount the ISO directly as virtual media instead of burning a USB — consult your BMC's documentation for the exact steps.

## 3. Boot the machine

Boot the target machine from the USB/virtual media (may require a one-time boot-order override in BIOS/UEFI). Talos boots into maintenance mode and the console prints its DHCP-assigned IP address — **write this down**, you need it for the next step.

The machine must also be reachable from wherever Terraform runs (CI, or locally) — directly, or via the Tailscale subnet router advertising its LAN, since CI's `talos` job joins the tailnet specifically to reach it.

## 4. Add it to Terraform

Terraform's Talos module addresses machines by IP directly (no Omni-style UUID identity/discovery service in between) and configures each one with a permanent **static** address — but a freshly booted machine only has the **DHCP** address from step 3, since the static one is itself delivered by the very first config apply. Add both to the relevant `control_plane_nodes`/`worker_nodes` list in `infra/terraform/talos-<cluster>.tf`:

```hcl
control_plane_nodes = [
  { name = "production-cp-1", ip = "10.1.245.21" }, # existing node
  { name = "production-cp-4", ip = "<new machine's intended permanent static IP>", bootstrap_ip = "<its DHCP IP from step 3>" },
]
```

Commit and merge to `main`. CI's `talos` job generates this machine's config (including the same installer image/system extensions as the rest of the cluster) and applies it directly — no separate claim/allocate step — but, with `bootstrap_ip` set, targets the machine's DHCP address for this one first apply rather than the static `ip` it's being configured with.

This first-time step has to happen from somewhere that can actually reach the machine's fresh DHCP address — the same reason `hsctl run -e local` exists in the automatron-removal PR: a human runs it from the LAN, not from CI, when CI's own Tailscale-routed reachability isn't enough (e.g. the subnet router isn't up yet, or the DHCP address is on a network segment CI can't reach).

## 5. Confirm it, then drop `bootstrap_ip`

Once CI's apply succeeds, confirm the machine now answers at its static IP (`talosctl -e <static-ip> -n <static-ip> version`, or similar). Then remove `bootstrap_ip` from its entry in a follow-up commit — every Terraform operation after that targets the static `ip` the same as every other machine in the cluster. See [Clusters: the DHCP/static-IP chicken-and-egg problem](../architecture/clusters.md#the-dhcpstatic-ip-chicken-and-egg-problem) for why this two-step dance exists.

See [Clusters: bootstrap a new cluster](../architecture/clusters.md#bootstrap-adding-a-new-cluster) if this is the first machine for a brand-new cluster rather than an addition to an existing one.
