# LonghornDiskFailed

**Severity:** Critical
**Alert:** `LonghornDiskFailed`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

Disk `$labels.disk` on node `$labels.node` has failed Longhorn's health check. Replicas scheduled on this disk are at risk, and Longhorn will stop scheduling new replicas to it.

## Common causes

| Cause | Fix |
|---|---|
| Underlying block device failure or I/O errors | Check `dmesg` / kernel logs on the node for disk errors |
| Disk unmounted or filesystem corruption on the node | SSH to the node and check the mount point Longhorn is configured to use |
| Disk full, causing health-check writes to fail | Check available space at the node's disk path |

## Remediation

1. `kubectl -n longhorn-system get nodes.longhorn.io <node> -o yaml` — find the failing disk's path and check `status.diskStatus.<disk>.conditions`.
2. SSH to the node (or check its console) and inspect the physical/virtual disk for hardware errors or a lost mount.
3. If the disk is unrecoverable, remove it from the node's Longhorn disk config so replicas are rebuilt elsewhere, then replace the underlying storage.
4. Watch [LonghornVolumeDegraded](longhorn-volume-degraded.md)/[LonghornVolumeFaulted](longhorn-volume-faulted.md) for any volumes that had a replica on the failed disk.
