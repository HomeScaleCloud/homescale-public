# OmniSecureBootDisabled

**Severity:** Warning
**Alert:** `OmniSecureBootDisabled`
**Dashboard:** [Omni](https://xxx/d/omni)

## What this means

`omni_machine_secure_boot_status{enabled="false"}` is greater than 0 — one or more machines registered in Omni are not booting with Secure Boot enabled.

Secure Boot ensures that only signed bootloaders and kernels can run on a machine, protecting against boot-time tampering and unauthorized code execution. Machines without Secure Boot do not meet the cluster's security baseline.

To identify which machine(s) are affected, check the Omni UI (reachable at `https://omni.<cluster>xxx` on the management cluster) — each machine's detail page shows its Secure Boot status.

## Common causes

| Cause | Fix |
|---|---|
| New bare-metal machine enrolled without Secure Boot configured in BIOS/UEFI | Access the machine's BMC console via the region's gw cluster, enable Secure Boot in UEFI, enroll the Talos signing keys, reboot |
| VM provisioned without Secure Boot (e.g., missing OVMF config) | Reconfigure the VM firmware to use UEFI with Secure Boot; re-enroll Talos keys |
| Machine was PXE-booted with a legacy BIOS path | Ensure the DHCP/TFTP config points to the UEFI bootloader, not the legacy one |
| Talos image does not include Secure Boot support | Use a Talos image built with `--with-secureboot` (via Image Factory) |

## Enabling Secure Boot on a bare-metal machine

1. Access the machine via its BMC (IPMI/iDRAC/iLO) through the gw cluster for its region
2. Power off the machine
3. In UEFI settings: enable Secure Boot, clear existing keys, enter Setup Mode
4. Boot the machine from the Talos PXE image — Talos will enroll its own signing keys on first boot
5. Verify in Omni that the machine reports `secureBootStatus: true` after re-enrollment

See [Talos Secure Boot documentation](https://www.talos.dev/latest/talos-guides/install/bare-metal-platforms/secureboot/) for key enrollment details.
