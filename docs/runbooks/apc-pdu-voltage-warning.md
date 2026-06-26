# ApcPduVoltageWarning

**Severity:** Warning
**Alert:** `ApcPduVoltageWarning`
**Dashboard:** [PDU Health](https://xxx/d/pdu-health)

## What this means

A PDU's input voltage has been outside the **198–218V** normal operating range for a 208V circuit for more than 2 minutes. The alert value (`$value`) is the measured voltage in volts.

This is a warning — equipment continues to operate, but sustained voltage deviation can shorten hardware lifespan and indicates a supply-side issue worth investigating. If voltage drops further, `ApcPduVoltageCritical` fires.

## Normal ranges

| Circuit | Normal | Warning threshold | Critical threshold |
|---|---|---|---|
| 208V (single-phase) | 198–218V | < 198V or > 218V | < 190V or > 225V |

## Common causes

| Symptom | Likely cause | Action |
|---|---|---|
| Voltage slowly declining | Facility load increasing on the circuit | Notify facilities; check breaker panel load |
| Voltage suddenly low | Upstream UPS switching to battery | Check UPS status; investigate utility power issue |
| Voltage high (> 218V) | Facility overvoltage or utility event | Monitor; if sustained, contact facilities |
| Oscillating voltage | Loose connection or failing breaker | Immediate facilities escalation |

## Escalation

If voltage is persistently out of range or trending toward the critical threshold, contact the facilities team. Do not attempt to adjust electrical infrastructure without qualified personnel.
