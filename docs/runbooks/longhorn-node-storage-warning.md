# LonghornNodeStorageWarning

**Severity:** Warning
**Alert:** `LonghornNodeStorageWarning`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

Node `$labels.node`'s total Longhorn storage (summed across its disks) is over 70% used. This is the node-level aggregate version of [LonghornDiskStorageWarning](longhorn-disk-storage-warning.md) — useful for spotting a node that's approaching capacity across all of its disks combined, not just one.

## Common causes and remediation

| Cause | Action |
|---|---|
| Replicas concentrated on this node relative to others in the cluster | Check per-disk breakdown on the [Longhorn Monitoring dashboard](https://REDACTED/d/ozk-lh-mon) and evict replicas from the fullest disk(s) to rebalance |
| Node has fewer/smaller disks than others in the pool | Consider adding a disk to the node, or treat it as lower-capacity in scheduling decisions |
| Genuine cluster-wide capacity growth | Plan additional storage capacity — see [LonghornDiskStorageCritical](longhorn-disk-storage-critical.md) for the immediate-risk version of this alert |
