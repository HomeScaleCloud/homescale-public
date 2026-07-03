# LonghornDiskStorageWarning

**Severity:** Warning
**Alert:** `LonghornDiskStorageWarning`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

Disk `$labels.disk` on node `$labels.node` is over 70% full. Longhorn is still able to schedule new replicas on it, but headroom is shrinking — at 90% it becomes [LonghornDiskStorageCritical](longhorn-disk-storage-critical.md), at which point Longhorn stops scheduling new replicas there.

## Common causes and remediation

| Cause | Action |
|---|---|
| Organic growth from replicas as app data grows | Check the Longhorn dashboard for which volumes have replicas on this disk and whether growth is expected |
| Uneven replica distribution across disks/nodes | Consider rebalancing by evicting a replica from the fullest disk (Longhorn UI → Node → disk → Edit → Scheduling) |
| Disk genuinely undersized for current workload | Plan a disk expansion or add another disk/node to the storage pool |

Check the trend on the [Longhorn Monitoring dashboard](https://REDACTED/d/ozk-lh-mon) — a slow steady climb is a capacity-planning issue; a sudden jump points to one volume's growth spike.
