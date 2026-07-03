# LonghornDiskStorageCritical

**Severity:** Critical
**Alert:** `LonghornDiskStorageCritical`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

Disk `$labels.disk` on node `$labels.node` is over 90% full. Longhorn will stop scheduling new replicas to this disk, and if it fills completely, existing replicas on it can fail I/O — risking [LonghornVolumeDegraded](longhorn-volume-degraded.md) or [LonghornVolumeFaulted](longhorn-volume-faulted.md) for volumes with a replica here.

## Immediate actions

1. Identify which volumes have a replica on the affected disk (Longhorn UI → Node → disk → Replicas, or `kubectl -n longhorn-system get replicas.longhorn.io -o wide | grep <node>`).
2. Evict one or more replicas off the disk to free space immediately (Longhorn UI → Node → disk → Edit node and disks → toggle **Eviction Requested**, or use `Disable scheduling` + evict).
3. If eviction isn't fast enough and the disk is at genuine risk of filling, identify and remove any reclaimable data on volumes backed by this disk (see [LonghornVolumeSpaceFilling](longhorn-volume-space-filling.md)).

## Longer-term fix

Add capacity — expand the underlying disk, add an additional disk to the node, or add another node to the storage pool — then rebalance replicas evenly across the larger pool.
