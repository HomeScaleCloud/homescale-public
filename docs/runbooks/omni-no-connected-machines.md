# OmniNoConnectedMachines

**Severity:** Critical
**Alert:** `OmniNoConnectedMachines`
**Dashboard:** [Omni](https://xxx/d/omni)

## What this means

`omni_connected_machines` has been 0 for 10 minutes. Omni itself is up and its metrics endpoint is reachable, but every machine has lost its SideroLink/WireGuard connection to Omni.

Connected machines dropping to zero means:
- Omni cannot push Talos config updates to any machine
- The `omni_connected_machines` timeseries shows a sudden cliff (not a gradual decline)
- Existing workloads continue running — the k8s control plane is not directly affected

## Diagnosis

```bash
# Check SideroLink service and LoadBalancer IP
kubectl -n omni get svc siderolink

# Verify the WireGuard advertised endpoint resolves and is reachable
dig xxx
nc -zu xxx 50180   # UDP — no output on success is normal

# Check for WireGuard-related errors in Omni logs
kubectl -n omni logs -l app.kubernetes.io/name=omni --tail=200 | grep -i "wireguard\|siderolink\|peer"

# Check the SideroLink last-handshake histogram in Grafana
# A spike in p99 latency followed by silence indicates a connectivity loss event
```

## Common causes

| Cause | Signs | Fix |
|---|---|---|
| SideroLink LoadBalancer IP changed | `kubectl get svc siderolink` shows a new IP | Update `external-dns` annotation or re-announce; machines re-register on next Omni restart |
| `xxx` DNS change | `dig` returns a different address than expected | Revert DNS change in Terraform |
| NetBird routing change broke UDP 50180 | Recent NetBird policy or subnet router change | Check NetBird peer access logs; restore routing |
| Omni WireGuard port blocked by firewall/ACL | UDP 50180 unreachable from machine subnets | Check boa1 BMC/MGMT subnet routing via boa1-gw |
| Omni pod restarted with new WireGuard keys | All peers show new handshake time of epoch | This is transient — machines re-negotiate; if persistent, check for key rotation in Omni config |

## Notes

- Machines reconnect automatically once the underlying network path is restored. No manual action on the machines is typically needed.
- If this coincided with a Terraform apply, check `infra/terraform/` for changes to NetBird or DNS resources.
