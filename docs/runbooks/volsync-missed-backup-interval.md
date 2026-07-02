# VolSyncMissedBackupInterval

**Severity:** Critical
**Alert:** `VolSyncMissedBackupInterval`
**Dashboard:** [VolSync](https://REDACTED/d/volsync)

## What this means

A VolSync `ReplicationSource` (or `ReplicationDestination`) did not complete a sync within its scheduled interval. `volsync_missed_intervals_total` incremented for this object in the last hour.

This is the primary signal that a backup silently stopped progressing — the CR may still exist and appear "fine" at a glance, but no new restic snapshot is being taken. If left unaddressed, a restore will only be possible from an increasingly stale point in time.

## Common causes

| Cause | Fix |
|---|---|
| VolumeSnapshot creation failing (CSI driver issue, no `VolumeSnapshotClass`, snapshot controller down) | Check `kubectl -n <namespace> describe replicationsource <name>` and events; check the CSI snapshotter/snapshot-controller pods |
| Mover job stuck or failing | See [VolSyncMoverJobFailed](volsync-mover-job-failed.md) |
| Restic repository unreachable (Backblaze B2 outage, bad credentials) | Check mover pod logs for restic errors; verify the `<app>-volsync-repo` secret is populated |
| Longhorn volume degraded/faulted, blocking snapshot | Check the Longhorn dashboard for the underlying PVC |
| PVC too large to complete within the mover job's timeout | Check mover pod logs for timeout errors; consider a longer schedule interval |

## Remediation

1. Identify the affected object from the alert's `obj_namespace`/`obj_name` labels.
2. `kubectl -n <obj_namespace> describe replicationsource <obj_name>` (or `replicationdestination`) — check `status.conditions` for the stuck condition and reason.
3. `kubectl -n <obj_namespace> get jobs,pods -l app.kubernetes.io/created-by=volsync` — check for a stuck or failing mover pod and inspect its logs.
4. Once the underlying issue (snapshot, network, repository) is fixed, VolSync will resume on its normal schedule — no manual re-trigger is needed.
5. If the PVC's data may already be at risk, treat this as urgent: confirm the most recent successful snapshot with `hsctl get snapshot <app>` before doing anything destructive to the running workload.
