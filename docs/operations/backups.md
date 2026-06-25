# Backups

VolSync (`apps/volsync/`, syncWave -5) provides PVC-level backup and restore via restic repositories.

## How backups work

Each app that needs backups has a `volsync.yaml` template gated by a Helm value. Under normal operation the `ReplicationSource` is active on a schedule. When restore mode is enabled the `ReplicationSource` is suppressed and replaced by a one-shot `ReplicationDestination`.

To override the backup schedule for a specific app:

```yaml
# apps/<app>/app.yaml
values:
  volsync:
    backupSchedule: "0 */2 * * *"  # every 2 hours
```

Restic credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, etc.) live in a secret named `<app>-volsync-repo` in the app's namespace, synced from Infisical at `/k8s/volsync/<cluster-name>/<app>`.

## Restore procedure

1. **List snapshots** (optional):
   ```bash
   hsctl volsync snapshot list <app>
   ```

2. **Scale down and enable restore** in `apps/<app>/app.yaml`:
   ```yaml
   clusters:
     mgmt:
       values:
         omni:
           replicaCount: 0
         volsync:
           restore:
             enabled: true
             restoreAsOf: "2024-01-15T00:00:00Z"  # latest snapshot at or before this time
             # previous: 3                         # or: Nth-most-recent
   ```

3. **Wait for completion**:
   ```bash
   kubectl -n <namespace> get replicationdestination <app>-restore -w
   ```
   Done when `.status.lastSyncTime` is set and `Reconciled=True`.

4. **Scale back up and disable restore** — remove both the scale-down and `volsync.restore` override in one commit. ArgoCD syncs, deletes the `ReplicationDestination`, recreates the `ReplicationSource`, and scales back up.
