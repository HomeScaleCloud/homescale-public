# VolSyncControllerDown

**Severity:** Critical
**Alert:** `VolSyncControllerDown`
**Dashboard:** [VolSync](https://REDACTED/d/volsync)

## What this means

The Prometheus scrape target for the VolSync controller (`volsync-metrics` service, `volsync-system` namespace) has been failing for 5 minutes. While `ReplicationSource`/`ReplicationDestination` CRs may still exist, the controller reconciling them may not be running — no new syncs will be scheduled or observed, and there is no metrics visibility into backup status for the whole cluster.

## Common causes

| Cause | Fix |
|---|---|
| Controller pod crash-looping | `kubectl -n volsync-system get pods` and check logs/events |
| Controller pod evicted (node pressure) | Check node conditions; the pod should reschedule automatically |
| kube-rbac-proxy/metrics port misconfigured after a chart upgrade | Check `apps/volsync/Chart.yaml` version and `volsync.metrics.disableAuth` value against the upstream chart's expectations |
| NetworkPolicy or CNI issue blocking the scrape | Check Cilium/network policy changes affecting `volsync-system` |

## Remediation

1. `kubectl -n volsync-system get pods` — confirm the controller pod is `Running` and not restarting.
2. `kubectl -n volsync-system logs deploy/volsync -f` (adjust deployment name if needed) for crash reasons.
3. `kubectl -n volsync-system get svc volsync-metrics` and confirm the Service has endpoints (`kubectl -n volsync-system get endpoints volsync-metrics`).
4. If the pod is healthy but the scrape still fails, check the `ServiceMonitor` (`volsync`) and Prometheus targets page for the specific scrape error (TLS, auth, timeout).
5. Once the controller is back up, existing `ReplicationSource`/`ReplicationDestination` CRs resume on their normal schedule automatically — no manual re-trigger is needed. Confirm with `hsctl get snapshot <app>` that new snapshots resume appearing.
