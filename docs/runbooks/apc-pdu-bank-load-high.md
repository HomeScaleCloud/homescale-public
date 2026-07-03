# ApcPduBankLoadHigh

**Severity:** Critical
**Alert:** `ApcPduBankLoadHigh`
**Dashboard:** [PDU Health](https://REDACTED/d/pdu-health)

## What this means

A PDU bank's current draw has exceeded **70% of its near-overload threshold** for 5 minutes. The alert fires per bank (`$labels.bank_index`). The alert value is the load as a percentage of the near-overload threshold.

This fires early, before the bank reaches the near-overload state (`ApcPduBankNearOverload`), so it can be acted on before the PDU itself reports a near-overload/overload condition. At 70% of the near-overload threshold there is still headroom, but adding more load or losing a circuit could push it over.

Check the PDU Health dashboard to see which bank is elevated and the load trend over time.

## Understanding PDU banks

APC AP7920 PDUs have per-bank circuit breakers. Each bank has a rated near-overload threshold (typically 80% of the breaker rating). The PDU reports `apc_rpdu_bank_load_state` states:

| State | Meaning |
|---|---|
| 1 | Normal |
| 2 | Near-overload |
| 3 | Overload |

## Common causes and remediation

| Cause | Action |
|---|---|
| New high-draw equipment added to the bank | Redistribute equipment to a less-loaded bank or PDU |
| Seasonal load increase (e.g., higher fan/cooling draw in summer) | Monitor trend; redistribute before hitting near-overload |
| Unexpected load spike from a misbehaving device | Identify the device via per-outlet monitoring on the PDU web UI; investigate |
| Load migration after another bank/PDU failed | Temporary; restore the failed path and rebalance |

## Capacity planning note

If load is trending upward over weeks, plan ahead — adding a circuit or redistributing rack load takes time to arrange with facilities.
