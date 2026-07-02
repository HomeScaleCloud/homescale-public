# NetBirdOperatorDown

**Severity:** Critical
**Alert:** `NetBirdOperatorDown`
**Dashboard:** [NetBird Operator](https://REDACTED/d/netbird-operator)

## What this means

The Prometheus scrape target for the NetBird operator (`netbird-netbird-operator-metrics` service, `netbird` namespace) has been failing for 5 minutes. `ClusterProxy`, `NetworkRouter`, and `NetworkResource` objects on this cluster will stop reconciling — new or changed mesh access, DNS zone registration, and service exposure will not take effect until the operator recovers.

## Common causes

| Cause | Fix |
|---|---|
| Operator pod crash-looping | `kubectl -n netbird get pods -l app.kubernetes.io/name=netbird-operator` and check logs/events |
| Both replicas down at once (rare, replicaCount: 2) | Check node conditions / scheduling pressure across the cluster |
| Webhook cert-manager certificate not renewed | Operator may fail readiness if serving certs are stale; check the webhook `Certificate` in the `netbird` namespace |
| NetBird API token invalid or rotated | Operator logs will show 401/403s from the NetBird management API; check the `netbird` secret's `NETBIRD_OPERATOR_TOKEN` key |

## Remediation

1. `kubectl -n netbird get pods -l app.kubernetes.io/name=netbird-operator` — confirm both replicas are `Running` and not restarting.
2. `kubectl -n netbird logs deploy/netbird-netbird-operator -f` for crash reasons or repeated API errors.
3. `kubectl -n netbird get svc netbird-netbird-operator-metrics` and confirm the Service has endpoints (`kubectl -n netbird get endpoints netbird-netbird-operator-metrics`).
4. If the pods are healthy but the scrape still fails, check the `ServiceMonitor` (`netbird-operator`) and the Prometheus targets page for the specific scrape error.
5. Once the operator is back up, existing `ClusterProxy`/`NetworkRouter`/`NetworkResource` objects reconcile automatically on their next resync — no manual re-trigger is needed.
