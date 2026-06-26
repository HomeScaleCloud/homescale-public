# OmniNoConnectedMachines

**Severity:** Critical
**Alert:** `OmniNoConnectedMachines`
**Dashboard:** [Omni](https://REDACTED/d/omni)

## What this means

`omni_connected_machines` has been 0 for 10 minutes. Omni itself is up and its metrics endpoint is reachable, but every machine has lost its SideroLink/WireGuard connection to Omni.

Zero connected machines means Omni cannot push Talos config updates to any machine. Existing workloads continue running — the k8s control plane is not directly affected — but this state should never occur under normal operation and requires immediate investigation.

## Notes

- If this coincided with a Terraform apply, check `infra/terraform/` for changes to NetBird or DNS resources.
- Machines reconnect automatically once the underlying network path is restored. No manual action on the machines is typically needed.
