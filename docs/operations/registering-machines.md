# Registering New Machines with Omni

This page walks through onboarding a new bare-metal machine so it can be claimed by a `cluster.yaml` in this repo.

## 1. Download installation media

1. Log in to Omni at [xxx](https://xxx).
2. Click **Download Installation Media** — this opens the "Create New Media" wizard.
3. Configure the schematic:
   - **Architecture** — `amd64`/`arm64` matching the target hardware
   - **Platform** — `metal` for bare metal
   - Any [system extensions](https://docs.siderolabs.com/talos/system-extensions/) needed at install time (e.g. `siderolabs/iscsi-tools`, `siderolabs/util-linux-tools` — check the target cluster's `systemExtensions` in `cluster.yaml` so the media matches)
   - Secure Boot, if the hardware supports it and you want it enforced (see the `OmniSecureBootDisabled` [runbook](../runbooks/omni-secure-boot-disabled.md) for what happens if it's skipped)
4. On the final "Schematic Ready" page, download the **ISO**.

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

Boot the target machine from the USB/virtual media (may require a one-time boot-order override in BIOS/UEFI). Talos boots into maintenance mode and the console prints its reachable IP address.

!!! warning
    The machine must be able to reach Omni outbound: UDP to the account's WireGuard port, or TCP 443 if using HTTP/2 tunneling. On our network this generally means it needs a route to `xxx` — machines in a region without direct connectivity go through that region's `*-gw` cluster (see [Gateway clusters](../architecture/networking.md#gateway-clusters)).

## 4. Confirm it registered

In the Omni UI, open the **Machines** menu — the new machine should appear shortly after boot, identified by its Talos/SMBIOS UUID. It shows as unallocated (not yet part of a cluster) until claimed.

Note the UUID — you'll need it for the next step.

```bash
# alternative: list machines from the CLI
omnictl get machines
```

## 5. Claim the machine in `cluster.yaml`

Add the UUID to the `machines:` list under the relevant `ControlPlane` (or worker) machine set in `clusters/<cluster>/cluster.yaml`:

```yaml
kind: ControlPlane
machines:
  - 4334c000-88da-11ea-8000-ac1f6be32b68 # existing node
  - <new-machine-uuid>
```

Commit and merge to `main`. CI runs the Omni template sync, which assigns the machine to the cluster and installs Talos + joins Kubernetes automatically.

See [Clusters: bootstrap a new cluster](../architecture/clusters.md#bootstrap-adding-a-new-cluster) if this is the first machine for a brand-new cluster rather than an addition to an existing one.
