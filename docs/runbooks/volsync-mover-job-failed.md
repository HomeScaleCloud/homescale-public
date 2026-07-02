# VolSyncMoverJobFailed

**Severity:** Critical
**Alert:** `VolSyncMoverJobFailed`
**Dashboard:** [VolSync](https://REDACTED/d/volsync)

## What this means

A VolSync mover `Job` (named `volsync-*`) reported `kube_job_status_failed`. The mover is the pod VolSync creates to actually move data — either taking a snapshot and pushing it to the restic repository (`ReplicationSource`) or pulling one down (`ReplicationDestination`). A failed job means that sync or restore attempt did not complete.

## Common causes

| Cause | Fix |
|---|---|
| VolumeSnapshot never became ready (CSI/snapshot-controller issue) | Check `kubectl -n <namespace> get volumesnapshot` for the mover's snapshot and its `READYTOUSE` status |
| restic repository auth failure | Check the `<app>-volsync-repo` secret and mover pod logs for `403`/auth errors |
| Mover pod OOMKilled or hit resource limits | `kubectl -n <namespace> describe pod <mover-pod>` for OOM/eviction events |
| restic repository lock contention (concurrent syncs) | Check for a stale lock; mover logs will mention `repository is already locked` |

## Remediation

1. `kubectl -n <namespace> get jobs -l app.kubernetes.io/created-by=volsync` — find the failed job named in the alert's `job_name` label.
2. `kubectl -n <namespace> logs job/<job_name>` — the restic/mover container logs almost always name the specific failure.
3. If it's a stuck restic lock: the mover has an `unlock` step built in on next run, but a persistently stuck lock may need manual `restic unlock` against the repository.
4. If it's a VolumeSnapshot problem, check the CSI snapshotter and `snapshot-controller` pods are healthy cluster-wide — this was the root cause of a prior incident where backups silently stopped across the whole cluster.
5. Delete the failed job (`kubectl -n <namespace> delete job <job_name>`) if it's blocking the next scheduled attempt — VolSync will recreate it on the next scheduled sync once the underlying issue is fixed.
