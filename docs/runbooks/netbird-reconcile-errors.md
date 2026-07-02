# NetBirdReconcileErrors

**Severity:** Warning
**Alert:** `NetBirdReconcileErrors`
**Dashboard:** [NetBird Operator](https://REDACTED/d/netbird-operator)

## What this means

The NetBird operator's `clusterproxy`, `networkrouter`, or `networkresource` controller (identified by `$labels.controller`) has logged reconcile errors in the last 15 minutes. The affected objects may still show `Ready` if a previous reconcile succeeded, so this can fire before (or without) a corresponding `NotReady` alert — it's an early signal that something is failing even if the last-known state still looks fine.

## Common causes

| Cause | Fix |
|---|---|
| NetBird management API rate limiting or auth failure | Operator logs show 401/403/429 responses from `api.netbird.io`; check the `NETBIRD_OPERATOR_TOKEN` secret and NetBird account status |
| Stale reference to a deleted group/router/service | Operator logs show a "not found" error for the referenced object; fix or remove the offending CR |
| Kubernetes API throttling on the operator's own client | Check `rest_client_requests_total` on the [NetBird Operator dashboard](https://REDACTED/d/netbird-operator) for a spike in non-2xx codes against the local API server |
| Webhook validation rejecting reconciled updates | Check `controller_runtime_webhook_requests_total` for failures around the same time |

## Remediation

1. `kubectl --context <cluster> -n netbird logs deploy/netbird-netbird-operator --since=15m | grep -i error` — find the specific object and error message.
2. Cross-reference the `controller` label with the affected CR kind (`clusterproxy`, `networkrouter`, `networkresource`) and inspect that specific object's `status.conditions`.
3. If the error references the NetBird management API, verify connectivity and credentials before assuming an operator bug.
4. This alert clears once `controller_runtime_reconcile_errors_total` stops incrementing for 15 minutes — no manual reset needed once the underlying cause is fixed.
