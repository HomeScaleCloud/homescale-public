# ApcPduBankNearOverload

**Severity:** Critical
**Alert:** `ApcPduBankNearOverload`
**Dashboard:** [PDU Health](https://REDACTED/d/pdu-health)

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

## If the circuit breaker has already tripped

1. Identify which bank tripped — affected outlets will have no power; the PDU front panel will show the bank in fault state.
2. Before resetting the breaker: ensure total load on that bank is below the rated threshold (physically unplug or power off devices as needed).
3. Reset the bank breaker on the PDU front panel or via the web UI (Outlet Group Control → reset).
4. Servers that lost power will need manual or IPMI-triggered power-on.

## PDU web UI access

The PDU management interface is reachable over NetBird via the region's gw cluster, which routes the region's BMC subnet.
