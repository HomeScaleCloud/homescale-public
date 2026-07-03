# LonghornVolumeFaulted

**Severity:** Critical
**Alert:** `LonghornVolumeFaulted`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

The Longhorn volume backing PVC `$labels.pvc_namespace`/`$labels.pvc` has robustness `faulted` — all of its replicas are unhealthy and the volume cannot serve I/O. Any pod mounting this PVC will be stuck or failing.

## Common causes

| Cause | Fix |
|---|---|
| All replicas lost their backing disk (node failure, disk removed) | Check `kubectl -n longhorn-system get replicas.longhorn.io -l longhornvolume=<volume>` for replica state and node/disk placement |
| Simultaneous multi-node outage during a replica rebuild | Restore the affected node(s); Longhorn will attempt to resume the rebuild once storage is reachable |
| Volume was force-detached during a disk/node failure | Check `kubectl -n longhorn-system get volumes.longhorn.io <volume> -o yaml` for `status.robustness` and `status.conditions` |

## Remediation

1. `kubectl -n longhorn-system get volumes.longhorn.io <volume> -o yaml` — check `status.robustness`, `status.currentNodeID`, and replica list.
2. `kubectl -n longhorn-system get replicas.longhorn.io -l longhornvolume=<volume>` — identify whether any replica is salvageable.
3. If all replicas are unrecoverable, use the Longhorn UI's **Salvage** action to attempt recovery from the least-stale replica, or restore the PVC from the most recent VolSync snapshot — see [Backups](../architecture/backups.md).
4. Once the volume is healthy again, confirm the owning pod remounts successfully (`kubectl -n <app-namespace> get pods`).
