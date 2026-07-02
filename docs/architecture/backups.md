# Backups

[VolSync](https://volsync.readthedocs.io/en/stable/) (`apps/volsync/`, syncWave -5) provides PVC-level backup and restore via [restic](https://restic.net/) repositories. VolSync runs as a Kubernetes operator; each app manages its own `ReplicationSource` (backup) and `ReplicationDestination` (restore) CRs via a `volsync.yaml` Helm template.

## How backups work

Each app that has a `volsync.yaml` template creates a `ReplicationSource` CR in its namespace. Under normal operation:

- The `ReplicationSource` runs on a cron schedule, snapshotting the app's PVC into a restic repository
- Snapshots are incremental — only changed blocks are sent
- Restic credentials are pulled from a Secret named `<app>-volsync-repo`, synced from Infisical at `/k8s/volsync/<cluster-name>/<app>`

When restore mode is enabled via `clusters/<cluster>/apps.yaml`, the `ReplicationSource` is suppressed and replaced by a one-shot `ReplicationDestination` that restores from a snapshot.

To override the backup schedule for a specific app:

```yaml
# apps/<app>/app.yaml
values:
  volsync:
    backupSchedule: "0 */2 * * *"  # every 2 hours (default: daily)
```

## Enabling backups for a new app

Per-app Infisical credentials are **managed automatically by Terraform** (`infra/terraform/volsync.tf`). Whenever Terraform detects an app with a `volsync.yaml` template it creates the Infisical folder at `/k8s/volsync/<cluster>/<app>/` and populates it with Infisical reference expressions that derive from shared base credentials at `/k8s/volsync/`:

| Derived key | Source |
|-------------|--------|
| `RESTIC_REPOSITORY` | `<shared-base-url>/<cluster>/<app>` |
| `RESTIC_PASSWORD` | Shared from `/k8s/volsync/RESTIC_PASSWORD` |
| `AWS_ACCESS_KEY_ID` | Shared from `/k8s/volsync/AWS_ACCESS_KEY_ID` |
| `AWS_SECRET_ACCESS_KEY` | Shared from `/k8s/volsync/AWS_SECRET_ACCESS_KEY` |

The shared base credentials must be configured once in Infisical at `/k8s/volsync/`. No per-app secret management is needed.

1. **Add a `volsync.yaml` template** to the app's Helm chart. Follow the pattern from an existing app (e.g. `apps/home-assistant/templates/volsync.yaml`). The template gates on `{{ .Values.volsync.enabled }}` and creates:
   - An `InfisicalSecret` CR to sync the restic credentials
   - A `ReplicationSource` CR for normal operation
   - A `ReplicationDestination` CR when `volsync.restore.enabled: true`

2. **Enable backups in `app.yaml`**:

    ```yaml
    values:
      volsync:
        enabled: true
        backupSchedule: "0 2 * * *"   # optional; default is daily
    ```

3. **Merge to `main`** — `terraform apply` creates the per-app Infisical paths. ArgoCD then deploys the `ReplicationSource` on the next sync.

## Restore procedure

### 1. Find the snapshot (optional)

```bash
hsctl get snapshot <app>
```

This lists available restic snapshots with their timestamps and IDs.

### 2. Scale down and enable restore

Edit `clusters/<cluster-name>/apps.yaml`'s `apps` source values to scale the app to zero and enable restore mode:

```yaml
# clusters/<cluster-name>/apps.yaml, spec.sources[1].helm.values
apps:
  <app>:
    values:
      myApp:
        replicaCount: 0
      volsync:
        restore:
          enabled: true
          # Choose one of:
          restoreAsOf: "2024-01-15T00:00:00Z"  # latest snapshot at or before this RFC3339 time
          # previous: 3                          # Nth-most-recent (1=latest, 2=second-latest, …)
```

Merge to `main`. ArgoCD syncs the change — the app scales to zero, and the `ReplicationDestination` CR is created.

### 3. Wait for completion

```bash
kubectl -n <namespace> get replicationdestination <app>-restore -w
```

The restore is complete when `.status.lastSyncTime` is set and conditions show `Reconciled=True`:

```
NAME             LAST SYNC TIME             ...
my-app-restore   2024-01-15T10:23:45Z       ...
```

### 4. Scale back up and disable restore

Remove both the `replicaCount: 0` override and the `volsync.restore` block from `clusters/<cluster>/apps.yaml` in a **single commit** and merge. ArgoCD syncs the change:

- Deletes the `ReplicationDestination`
- Recreates the `ReplicationSource` (backups resume)
- Scales the deployment back up against the restored PVC

!!! warning "Always remove both overrides in one commit"
    Removing scale-down without removing restore, or vice versa, leaves the app in an inconsistent state. Bundle them in a single commit so ArgoCD applies the transition atomically.

## Monitoring

VolSync's controller exports Prometheus metrics (`volsync_volume_out_of_sync`, `volsync_missed_intervals_total`, sync duration) that are scraped in every cluster and forwarded to the central [VolSync Grafana dashboard](https://REDACTED/d/volsync), which also surfaces mover job failures and bound PVCs with no `ReplicationSource`.

Alerting rules (`apps/metrics/templates/prometheusrule-volsync.yaml`) fire if a backup misses its scheduled interval, a mover job fails, or the controller itself becomes unreachable — see the [VolSync runbooks](../runbooks/index.md#volsync) for each alert.

## Restic repository storage

HomeScale uses Backblaze B2 via its S3-compatible API. Each app gets its own prefix appended to a shared base URL:

```
<RESTIC_REPOSITORY>/<cluster>/<app>
```

where `RESTIC_REPOSITORY` is the shared base URL stored in Infisical at `/k8s/volsync/RESTIC_REPOSITORY`. Terraform derives per-app repository paths automatically — no manual path configuration is needed when adding a new app.

Credentials are stored in Infisical at `/k8s/volsync/` and synced per-app to `/k8s/volsync/<cluster>/<app>/`:

| Secret | Description |
|---|---|
| `RESTIC_REPOSITORY` | Full B2 S3-compatible URL + `/<cluster>/<app>` suffix |
| `RESTIC_PASSWORD` | Shared restic encryption passphrase |
| `AWS_ACCESS_KEY_ID` | Backblaze B2 application key ID |
| `AWS_SECRET_ACCESS_KEY` | Backblaze B2 application key |
