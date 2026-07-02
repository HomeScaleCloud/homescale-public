# NetBirdWorkqueueBacklog

**Severity:** Warning
**Alert:** `NetBirdWorkqueueBacklog`
**Dashboard:** [NetBird Operator](https://REDACTED/d/netbird-operator)

## What this means

The NetBird operator's `clusterproxy`, `networkrouter`, or `networkresource` controller (identified by `$labels.name`) has held a backlog of more than 5 queued items for 15 minutes. Reconciles for that CR kind are falling behind — changes to `ClusterProxy`/`NetworkRouter`/`NetworkResource` objects on this cluster may take longer than expected to take effect, or a specific item may be stuck retrying.

## Common causes

| Cause | Fix |
|---|---|
| A single object is stuck retrying (crash-loop reconcile) | Check `NetBirdReconcileErrors` for the same controller — a repeatedly failing reconcile keeps re-queuing itself |
| Bulk change (e.g. many `NetworkResource`s created/updated at once) | Transient; should drain on its own as the operator catches up |
| NetBird management API slow to respond | Check `rest_client_requests_total` latency/error rate on the [dashboard](https://REDACTED/d/netbird-operator) |
| Operator under-resourced or CPU-throttled | `kubectl -n netbird top pods -l app.kubernetes.io/name=netbird-operator` |

## Remediation

1. `kubectl --context <cluster> -n netbird logs deploy/netbird-netbird-operator --since=15m | grep -i <controller-name>` — look for repeated reconciles of the same object.
2. If one object is stuck, inspect it directly (`kubectl get <kind> -A -o yaml`) for a bad reference or invalid spec causing perpetual retries.
3. If the backlog is broad (many different objects), check NetBird API latency/errors before assuming an operator problem.
4. The queue drains automatically once the underlying cause is resolved — no manual intervention needed beyond fixing the root cause.
