# ApcPduVoltageCritical

**Severity:** Critical
**Alert:** `ApcPduVoltageCritical`
**Dashboard:** [PDU Health](https://xxx/d/pdu-health)

## What this means

A PDU's input voltage has been outside the **190–225V** critical limit for a 208V circuit for more than 2 minutes. At these levels, equipment PSUs may shut down, behave erratically, or sustain damage. Immediate action is required.

The alert value (`$value`) is the current measured voltage.

## Thresholds

| Condition | Threshold | Risk |
|---|---|---|
| Critically low | < 190V | PSUs may drop out; servers may shut down or restart |
| Critically high | > 225V | PSUs and other equipment may be damaged |

## Immediate actions

1. **Check whether equipment is already shutting down** — check `kubectl get nodes` for any nodes going `NotReady` and check power state via IPMI/BMC.

2. **Check UPS status** — critically low voltage may indicate the UPS is on battery and nearing exhaustion. Check the UPS management interface.

3. **Do not restart equipment** while voltage is unstable — a PSU restart into low voltage can cause further damage.

4. **Notify facilities immediately** — voltage this far out of range is a facility infrastructure issue.

## Common causes

| Symptom | Likely cause |
|---|---|
| Voltage dropped suddenly to ~0V | Complete loss of utility power; UPS may be engaged |
| Voltage low but non-zero (e.g., 170V) | Utility brownout or heavily loaded circuit |
| Voltage high (> 225V) | Utility overvoltage event or wiring fault |

## Escalation

This requires immediate facilities escalation. If equipment is shutting down and a graceful cluster drain is needed, initiate it now before power is fully lost — a controlled shutdown is safer than an abrupt power-off.
