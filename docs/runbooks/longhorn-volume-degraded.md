# LonghornVolumeDegraded

**Severity:** Warning
**Alert:** `LonghornVolumeDegraded`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

The Longhorn volume backing PVC `$labels.pvc_namespace`/`$labels.pvc` has robustness `degraded` — at least one replica is unavailable or rebuilding. The volume still serves I/O, but redundancy is reduced; a second replica loss would fault it (see [LonghornVolumeFaulted](longhorn-volume-faulted.md)).

## Common causes

| Cause | Fix |
|---|---|
| A replica's node went down or was drained | Longhorn schedules a replacement replica automatically once a healthy node/disk is available |
| A replica is actively rebuilding after a prior fault | Expected and self-resolving; check rebuild progress in the Longhorn UI |
| Disk pressure prevented scheduling a replacement replica | See [LonghornDiskStorageWarning](longhorn-disk-storage-warning.md) / [LonghornDiskStorageCritical](longhorn-disk-storage-critical.md) |
| Not enough eligible nodes for the volume's replica count | Check node/disk tags and `kubectl -n longhorn-system get nodes.longhorn.io` for scheduling eligibility |

## Remediation

1. `kubectl -n longhorn-system get replicas.longhorn.io -l longhornvolume=<volume>` — identify which replica is down or rebuilding.
2. If a replica is rebuilding, no action is needed — wait for it to complete (progress visible in the Longhorn UI).
3. If a replica is stuck (not rebuilding and not scheduled), check for disk space or node eligibility issues on remaining nodes.
4. If the alert persists beyond a normal rebuild window (tens of minutes for typical volume sizes), escalate before a second replica loss faults the volume.
