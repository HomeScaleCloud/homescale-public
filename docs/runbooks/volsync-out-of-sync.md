# VolSyncOutOfSync

**Severity:** Warning
**Alert:** `VolSyncOutOfSync`
**Dashboard:** [VolSync](https://REDACTED/d/volsync)

## What this means

`volsync_volume_out_of_sync` has been `1` for this object for 6 hours. The volume's data has diverged from the last completed sync and backups are not catching up.

This is a softer, slower-burning signal than [VolSyncMissedBackupInterval](volsync-missed-backup-interval.md) — the object may still be completing syncs, just not fast enough to ever catch the volume back up to "in sync".

## Common causes

| Cause | Fix |
|---|---|
| Sync duration exceeds the schedule interval (large/high-churn volume) | Check "Sync Duration per Volume" on the VolSync dashboard; consider a longer `backupSchedule` |
| Intermittent sync failures (retrying but not completing) | Check for a pattern in mover job history; see [VolSyncMoverJobFailed](volsync-mover-job-failed.md) |
| Restic repository under load or throttled | Check mover pod logs for slow/retried B2 requests |

## Remediation

1. Check the "Sync Duration per Volume" panel on the [VolSync dashboard](https://REDACTED/d/volsync) for the affected object — if sync duration is close to or exceeds the schedule interval, that's the root cause.
2. `kubectl -n <obj_namespace> get replicationsource <obj_name> -o yaml` — check `status.lastSyncTime` and `status.lastSyncDuration`.
3. If syncs are simply too slow for the schedule, widen `volsync.backupSchedule` in the app's `app.yaml`.
4. If syncs are failing intermittently, follow [VolSyncMoverJobFailed](volsync-mover-job-failed.md) to diagnose the mover job.
