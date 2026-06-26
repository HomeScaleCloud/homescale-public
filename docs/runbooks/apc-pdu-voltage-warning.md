# ApcPduVoltageWarning

**Severity:** Warning
**Alert:** `ApcPduVoltageWarning`
**Dashboard:** [PDU Health](https://REDACTED/d/pdu-health)

## What this means

A PDU's input voltage has been outside the **198–218V** normal operating range for a 208V circuit for more than 2 minutes. The alert value (`$value`) is the measured voltage in volts.

This is a warning — equipment continues to operate, but sustained voltage deviation can shorten hardware lifespan and indicates a supply-side issue worth investigating. If voltage drops further, `ApcPduVoltageCritical` fires.

## Normal ranges

| Circuit | Normal | Warning threshold | Critical threshold |
|---|---|---|---|
| 208V (single-phase) | 198–218V | < 198V or > 218V | < 190V or > 225V |

## Diagnosis

```bash
# Check current voltage reading via SNMP
kubectl -n metrics exec -it deploy/snmp-exporter -- \
  snmpget -v1 -c public 10.1.246.5 1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.1

# Or query Prometheus directly
curl -sG 'http://prometheus.metrics.svc.cluster.local:9090/api/v1/query' \
  --data-urlencode 'query=apc_rpdu_input_voltage_volts{job="pdu_01_boa1"}' \
  | jq '.data.result[].value[1]'
```

Check the PDU Health dashboard for the voltage trend — a gradual drift vs. a sudden spike indicates different underlying causes.

## Common causes

| Symptom | Likely cause | Action |
|---|---|---|
| Voltage slowly declining | Facility load increasing on the circuit | Notify facilities; check breaker panel load |
| Voltage suddenly low | Upstream UPS switching to battery | Check UPS status; investigate utility power issue |
| Voltage high (> 218V) | Facility overvoltage or utility event | Monitor; if sustained, contact facilities |
| Oscillating voltage | Loose connection or failing breaker | Immediate facilities escalation |

## Escalation

If voltage is persistently out of range or trending toward the critical threshold, contact the facilities team. Do not attempt to adjust electrical infrastructure without qualified personnel.
