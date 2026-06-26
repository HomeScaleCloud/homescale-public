# OmniNoConnectedMachines

**Severity:** Critical
**Alert:** `OmniNoConnectedMachines`
**Dashboard:** [Omni](https://xxx/d/omni)

## What this means

`omni_connected_machines` has been 0 for 10 minutes. Omni itself is up and its metrics endpoint is reachable, but every machine has lost its SideroLink/WireGuard connection to Omni.

Connected machines dropping to zero means Omni cannot push Talos config updates to any machine. The `omni_connected_machines` timeseries will show a sudden cliff rather than a gradual decline. Existing workloads continue running — the k8s control plane is not directly affected.

## Common causes

| Cause | Fix |
|---|---|
| SideroLink LoadBalancer IP changed | Update the `external-dns` annotation or re-announce; machines re-register on next Omni restart |
| `xxx` DNS changed | Revert the DNS change in Terraform |
| NetBird routing change broke UDP 50180 | Check NetBird peer access logs; restore routing |
| Omni pod restarted with new WireGuard keys | Transient — machines re-negotiate automatically; if persistent, check for key rotation in Omni config |

## Notes

- Machines reconnect automatically once the underlying network path is restored. No manual action on the machines is typically needed.
- If this coincided with a Terraform apply, check `infra/terraform/` for changes to NetBird or DNS resources.
