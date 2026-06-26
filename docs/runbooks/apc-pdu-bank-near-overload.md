# ApcPduBankNearOverload

**Severity:** Critical
**Alert:** `ApcPduBankNearOverload`
**Dashboard:** [PDU Health](https://xxx/d/pdu-health)

## What this means

The PDU itself is reporting a bank as **near-overload (state 2) or overload (state 3)**. The alert value indicates the state: `2` = near-overload, `3` = overload.

This is a critical alert because:
- **Near-overload (2):** The bank is above the PDU's near-overload threshold. The bank circuit breaker may trip if load increases further.
- **Overload (3):** The bank is above the PDU's overload threshold. The circuit breaker is likely to trip imminently, cutting power to everything on that bank without warning.

## Immediate actions

**For overload (state 3) — act now:**

1. Identify which PDU and bank: `$labels.job` (PDU) and `$labels.bank_index` (bank number).
2. Identify what is plugged into that bank — use the PDU web UI (`http://10.1.246.5` or `.6`) → Outlet Control to see per-outlet current.
3. Power off or relocate the highest-draw non-critical device on that bank immediately.
4. Do not simply silence the alert — the circuit breaker may trip at any moment, causing an uncontrolled shutdown.

**For near-overload (state 2):**

1. Identify the bank and its current load (see PDU Health dashboard).
2. Redistribute load — move a device to another bank or PDU before load increases further.
3. Check whether `ApcPduBankLoadHigh` fired earlier and was not acted on.

## Diagnosis

```bash
# Check bank load states across both PDUs
kubectl -n metrics exec -it deploy/snmp-exporter -- \
  snmpwalk -v1 -c public 10.1.246.5 1.3.6.1.4.1.318.1.1.12.3.5.1.1.3

# Query bank states in Prometheus
curl -sG 'http://prometheus.metrics.svc.cluster.local:9090/api/v1/query' \
  --data-urlencode 'query=apc_rpdu_bank_load_state{job=~"pdu_.*"}' \
  | jq '.data.result[] | {job: .metric.job, bank: .metric.bank_index, state: .value[1]}'

# Current load per bank in amps
curl -sG 'http://prometheus.metrics.svc.cluster.local:9090/api/v1/query' \
  --data-urlencode 'query=apc_rpdu_bank_load_deciamps / 10' \
  | jq '.data.result[] | {job: .metric.job, bank: .metric.bank_index, amps: .value[1]}'
```

## If the circuit breaker has already tripped

1. Identify which bank tripped — affected outlets will have no power; the PDU front panel will show the bank in fault state.
2. Before resetting the breaker: ensure total load on that bank is below the rated threshold (physically unplug or power off devices as needed).
3. Reset the bank breaker on the PDU front panel or via the web UI (Outlet Group Control → reset).
4. Servers that lost power will need manual or IPMI-triggered power-on.

## PDU web UI access

The PDU management interface is at `http://10.1.246.5` and `http://10.1.246.6`, reachable via the `boa1-gw` NetBird subnet router on the BOA1 MGMT subnet (`10.1.246.0/24`).
