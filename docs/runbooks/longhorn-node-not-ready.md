# LonghornNodeNotReady

**Severity:** Critical
**Alert:** `LonghornNodeNotReady`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

Node `$labels.node` is reporting `ready: false` in Longhorn specifically (the Kubernetes node itself may still be `Ready`). This usually means the `longhorn-manager` or `longhorn-instance-manager` pod on that node is unhealthy, even though the underlying host is up.

## Common causes

| Cause | Fix |
|---|---|
| `longhorn-manager` pod crash-looping on the node | `kubectl -n longhorn-system get pods -l app=longhorn-manager -o wide`, check logs on the affected node's pod |
| `longhorn-instance-manager` pod unhealthy | `kubectl -n longhorn-system get pods -l longhorn.io/component=instance-manager -o wide` |
| Node under resource pressure preventing Longhorn pods from running | `kubectl describe node <node>` for pressure conditions |

## Remediation

1. Confirm the underlying Kubernetes node is `Ready`: `kubectl get node <node>`.
2. Check Longhorn's manager and instance-manager pods on that node for crash loops or pending state.
3. Restart the affected pod(s) if logs show a transient error; investigate resource pressure or node conditions if pods can't schedule.
4. Once Longhorn's manager reports the node ready again, it resumes scheduling replicas there.
