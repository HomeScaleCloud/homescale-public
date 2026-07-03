# Backups

[VolSync](https://volsync.readthedocs.io/en/stable/) (`apps/volsync/`, syncWave -5) provides PVC-level backup and restore via [restic](https://restic.net/) repositories. VolSync runs as a Kubernetes operator; each app manages its own `ReplicationSource` (backup) and `ReplicationDestination` (restore) CRs via a `volsync.yaml` Helm template.

## How backups work

Each app that has a `volsync.yaml` template creates a `ReplicationSource` CR in its namespace. Under normal operation:

- The `ReplicationSource` runs on a cron schedule, snapshotting the app's PVC into a restic repository
- Snapshots are incremental — only changed blocks are sent
- Restic credentials are pulled from a Secret named `<app>-volsync-repo`, synced from a shared Infisical path (`/k8s/volsync`) with the per-app repository suffix computed in the Helm template — see [VolSync secrets](secrets.md#volsync-secrets) for the exact mechanism

When restore mode is enabled via `clusters/<cluster>/apps.yaml`, the `ReplicationSource` is suppressed and replaced by a one-shot `ReplicationDestination` that restores from a snapshot.

To override the backup schedule for a specific app:

```yaml
# apps/<app>/app.yaml
values:
  volsync:
    backupSchedule: "0 */2 * * *"  # every 2 hours (default: daily)
```

## Enabling backups for a new app

No per-app Infisical setup is needed — every app's `InfisicalSecret` CR reads the same shared credentials at `/k8s/volsync` and computes its own repository suffix at Helm-template time (`RESTIC_REPOSITORY: "{{ .RESTIC_REPOSITORY.Value }}/{{ .Values.cluster.name }}/<app>"`). See [VolSync secrets](secrets.md#volsync-secrets) for the exact CR pattern.

The shared base credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) must be configured once in Infisical at `/k8s/volsync`.

!!! note "Terraform also scaffolds a per-app path that isn't consumed"
    `infra/terraform/volsync.tf` additionally creates a per-app folder at `/k8s/volsync/<cluster>/<app>/` with derived reference-expression secrets. No shipped app actually points its `InfisicalSecret` at that path — this is worth knowing about but isn't part of the working setup flow below.

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

This lists available restic snapshots with their timestamps and IDs. See the [hsctl reference](../operations/hsctl.md) for other subcommands.

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

`RESTIC_REPOSITORY` is the shared base URL stored in Infisical at `/k8s/volsync`; the `/<cluster>/<app>` suffix is appended by each app's Helm chart at template time (via `managedKubeSecretReferences[].template.data`), not by Terraform — see [VolSync secrets](secrets.md#volsync-secrets).

Credentials are stored in Infisical at `/k8s/volsync` and read directly (via `includeAllSecrets: true`) by every app's `InfisicalSecret` CR:

| Secret | Description |
|---|---|
| `RESTIC_REPOSITORY` | Base B2 S3-compatible URL, without a per-app suffix |
| `RESTIC_PASSWORD` | Shared restic encryption passphrase |
| `AWS_ACCESS_KEY_ID` | Backblaze B2 application key ID |
| `AWS_SECRET_ACCESS_KEY` | Backblaze B2 application key |
