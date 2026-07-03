# LonghornDiskNotReady

**Severity:** Critical
**Alert:** `LonghornDiskNotReady`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

Disk `$labels.disk` on node `$labels.node` is reporting `ready: false` in Longhorn. Unlike [LonghornDiskFailed](longhorn-disk-failed.md) (a health-check failure), this typically means the disk isn't currently usable for scheduling — it may be initializing, unmounted, or unreachable.

## Common causes

| Cause | Fix |
|---|---|
| Node was recently rebooted and the disk hasn't remounted yet | Check the mount on the node; Longhorn should recover once the mount returns |
| Disk path misconfigured or removed from the node | Check `kubectl -n longhorn-system get nodes.longhorn.io <node> -o yaml` under `spec.disks` |
| longhorn-manager pod on that node is down or restarting | `kubectl -n longhorn-system get pods -l app=longhorn-manager -o wide` and check the pod on the affected node |

## Remediation

1. `kubectl -n longhorn-system get nodes.longhorn.io <node> -o yaml` — check `status.diskStatus.<disk>.conditions` for the specific reason.
2. Confirm the disk is mounted on the node at the path Longhorn expects.
3. Restart the `longhorn-manager` pod on that node if it's the one reporting stale status.
4. If the disk was intentionally removed, delete its entry from the node's Longhorn disk config to stop the alert.
