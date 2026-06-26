# ApcPduOffline

**Severity:** Critical
**Alert:** `ApcPduOffline`
**Dashboard:** [PDU Health](https://xxx/d/pdu-health)

## What this means

SNMP scrapes for a PDU have been failing for 3 minutes. The SNMP exporter on the region's gw cluster cannot reach the PDU's management interface. The PDU itself may be operational (powering equipment), but its management plane is unreachable — power state, load, and voltage can no longer be monitored or controlled remotely.

The alert fires per PDU (`$labels.job` / `$labels.instance`). Currently monitored PDUs:

| Job | Address | Location |
|---|---|---|
| `pdu_01_boa1` | `10.1.246.5` | BOA1 rack |
| `pdu_02_boa1` | `10.1.246.6` | BOA1 rack |

## Common causes

| Cause | Fix |
|---|---|
| PDU management card rebooting | Transient; recovers on its own within a few minutes — silence the alert if planned maintenance |
| PDU management card crashed or firmware issue | Power-cycle just the management card (hold the card reset button); check card LED for fault state |
| BMC VLAN or subnet routing issue | Other devices on the BMC subnet are also unreachable — check the region's gw cluster subnet router config and the physical switch port |
| PDU powered off entirely | Physical inspection of the PDU and upstream circuit breaker |
| SNMP community string changed | Other SNMP metrics also missing — verify `snmpv1_public` community string matches PDU config; update via PDU web UI |

## Physical access

The PDUs are in the BOA1 rack. If remote management is unavailable, the PDU display panel shows current load and outlet status. The `boa1-gw` cluster provides subnet routing to the BOA1 BMC subnet (`10.1.246.0/24`) via NetBird — if that route is down, access the PDU directly from a machine on the same VLAN.
