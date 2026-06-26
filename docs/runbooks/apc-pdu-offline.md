# ApcPduOffline

**Severity:** Critical
**Alert:** `ApcPduOffline`
**Dashboard:** [PDU Health](https://xxx/d/pdu-health)

## What this means

SNMP scrapes for a PDU have been failing for 3 minutes. The SNMP exporter on `boa1-gw` cannot reach the PDU's management interface. The PDU itself may be operational (powering equipment), but its management plane is unreachable — power state, load, and voltage can no longer be monitored or controlled remotely.

The alert fires per PDU (`$labels.job` / `$labels.instance`). Currently monitored PDUs:

| Job | Address | Location |
|---|---|---|
| `pdu_01_boa1` | `10.1.246.5` | BOA1 rack |
| `pdu_02_boa1` | `10.1.246.6` | BOA1 rack |

## Diagnosis

```bash
# Check SNMP reachability from boa1-gw (requires NetBird access to boa1)
kubectl -n metrics exec -it deploy/snmp-exporter -- \
  snmpwalk -v1 -c public 10.1.246.5 1.3.6.1.2.1.1.1

# Check recent SNMP exporter logs
kubectl -n metrics logs -l app=snmp-exporter --tail=100

# Verify the SNMP exporter scrape target is healthy
curl -s "http://snmp-exporter.metrics.svc.cluster.local:9116/snmp?target=10.1.246.5&module=apc_rpdu&auth=snmpv1_public"

# Check if the management interface IP is reachable at all
# (from a pod with access to the boa1 MGMT subnet via boa1-gw)
ping -c 3 10.1.246.5
```

## Common causes

| Cause | Signs | Fix |
|---|---|---|
| PDU management card rebooting | Transient; recovers on its own within a few minutes | Wait; silence alert if planned maintenance |
| PDU management card crashed or firmware issue | Persistent; physical access shows card LED error | Power-cycle just the management card (hold the card reset button) |
| MGMT VLAN or subnet routing issue | Other devices on 10.1.246.x also unreachable | Check boa1-gw subnet router NetBird config and physical switch port |
| PDU powered off entirely | All outlets unpowered; catastrophic | Physical inspection of the PDU and upstream circuit breaker |
| SNMP community string changed | Other SNMP metrics also missing | Verify `snmpv1_public` community string matches PDU config; update via PDU web UI |

## Physical access

The PDUs are in the BOA1 rack. If remote management is unavailable, the PDU display panel shows current load and outlet status. The `boa1-gw` node provides subnet routing to `10.1.246.0/24` (MGMT subnet) via NetBird — if that route is down, access the PDU directly from a machine on the same VLAN.
