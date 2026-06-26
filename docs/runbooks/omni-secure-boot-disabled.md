# OmniSecureBootDisabled

**Severity:** Warning
**Alert:** `OmniSecureBootDisabled`
**Dashboard:** [Omni](https://REDACTED/d/omni)

## What this means

`omni_machine_secure_boot_status{status="false"}` is greater than 0 — one or more machines registered in Omni are not booting with Secure Boot enabled.

Secure Boot ensures that only signed bootloaders and kernels can run on a machine, protecting against boot-time tampering and unauthorized code execution. Machines without Secure Boot do not meet the cluster's security baseline.

## Diagnosis

Omni's metrics expose aggregate counts only — there is no per-machine label on this metric. To identify which machine(s) have Secure Boot disabled:

```bash
# List all machines with their secure boot status
omnictl get machinestatus -o yaml | grep -A5 "secureBootStatus"

# Or use JSON output for easier parsing
omnictl get machinestatus -o json | \
  jq '.items[] | {name: .metadata.id, secureBoot: .spec.hardware.blockdevices}'
```

You can also check the Omni UI at `https://REDACTED` — machine details show Secure Boot status on each machine's page.

## Common causes

| Cause | Fix |
|---|---|
| New bare-metal machine enrolled without Secure Boot configured in BIOS/UEFI | Access the machine's BMC console, enable Secure Boot in UEFI, enroll the Talos signing keys, reboot |
| VM provisioned without Secure Boot (e.g., missing OVMF config) | Reconfigure the VM firmware to use UEFI with Secure Boot; re-enroll Talos keys |
| Machine was PXE-booted with a legacy BIOS path | Ensure the DHCP/TFTP config points to the UEFI bootloader, not the legacy one |
| Talos image does not include Secure Boot support | Use a Talos image built with `--with-secureboot` (via Image Factory) |

## Enabling Secure Boot on a machine

1. Access the machine via its BMC (IPMI/iDRAC/iLO) through the `boa1-gw` subnet router
2. Power off the machine
3. In UEFI settings: enable Secure Boot, clear existing keys, enter Setup Mode
4. Boot the machine from the Talos PXE image — Talos will enroll its own signing keys on first boot
5. Verify in Omni that the machine reports `secureBootStatus: true` after re-enrollment

See [Talos Secure Boot documentation](https://www.talos.dev/latest/talos-guides/install/bare-metal-platforms/secureboot/) for key enrollment details.
