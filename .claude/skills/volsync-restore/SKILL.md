---
name: volsync-restore
description: Use when restoring an app's PVC(s) from a VolSync/restic backup, rolling back a completed restore, or troubleshooting a stuck restore. Covers finding a snapshot, safely scaling the app to zero (with rendered-manifest verification, not just trusting the YAML edit), running the restore, and cleanly rolling back to normal operation afterward.
---

# VolSync restore

This is a two-phase, two-commit operation (restore in, then roll back out) described in CLAUDE.md's "VolSync Backups" section. The dangerous part isn't the restore itself — it's a scale-down override that silently doesn't take effect (wrong value path, wrong chart section) while a pod keeps writing to the PVC that VolSync is about to overwrite. **Always verify the rendered manifest before pushing, both going in and coming back out.**

A helper script for that verification is bundled at `scripts/render-check.sh` — see step 3 and step 6.

## 1. Identify the app and its PVC(s)

Check `apps/<app>/templates/volsync.yaml`:
- **Single PVC** (e.g. `apps/omni`): the PVC name matches the app name, restic secret is `<app>-volsync-repo`.
- **Multi-PVC** (e.g. `apps/home-assistant`): the template has a `$pvcs := list "..." "..."` at the top — each PVC gets its own `ReplicationSource`/`ReplicationDestination` and its own `<pvc>-volsync-repo` secret. Note which PVCs need `moverSecurityContext` overrides (uid/gid) — check the template for `{{- if eq . "<pvc>" }}` blocks; get those uid/gid values right if you add a new PVC that needs one.

## 2. Find the snapshot you want to restore (optional)

```bash
hsctl get snapshot <app>
```

This looks up `apps/<app>/app.yaml` for the namespace and reads the secret `<app>-volsync-repo` — it only works when the app directory name matches the PVC name. For a multi-PVC app's non-primary PVCs (e.g. `zigbee2mqtt` under `home-assistant`), there's no `apps/zigbee2mqtt/app.yaml` to resolve, so `hsctl get snapshot` can't be used directly — adapt `get_snapshot()` in `hsctl.d/get.sh` by hand (swap in the right namespace and `<pvc>-volsync-repo` secret name) or run the equivalent restic-pod-in-that-namespace manually.

Note the snapshot time (for `restoreAsOf`) or count back from latest (for `previous`) if you don't want the latest snapshot.

## 3. Determine the correct scale-down field — don't guess it

Read the app's actual chart values (its `values.yaml`, or the upstream subchart's, under `apps/<app>/charts/`) to find the real replica-count path. It varies: `apps/omni/app.yaml` uses `values.omni.replicaCount`, but another chart might use a bare `replicaCount`, `controller.replicaCount`, or something else entirely depending on the upstream chart's conventions. A wrong path merges into the override silently — no error, no warning — and the app keeps running at its normal replica count while VolSync overwrites the PVC underneath it.

## 4. Edit `clusters/<cluster>/apps.yaml` — scale-down and restore together

In the app's override block, add **both** the scale-down and the `volsync.restore` block in the same change:

```yaml
apps:
  <app>:
    values:
      <app>:
        replicaCount: 0          # exact path from step 3
      volsync:
        restore:
          enabled: true
          restoreAsOf: "2024-01-15T00:00:00Z"  # optional — omit for latest
          # previous: 3                          # or: Nth-most-recent, alternative to restoreAsOf
```

Remember the deep-merge/list-replace rule: if the app already has a `values:` block in this cluster's override, you're adding keys into it, not replacing it — but any list-valued field you touch replaces the base's list wholesale.

## 5. Verify locally, before pushing

```bash
.claude/skills/volsync-restore/scripts/render-check.sh <cluster> <app>
```

Confirm the output shows:
- the app's Deployment/StatefulSet at `replicas: 0`
- a `ReplicationDestination` named `<app>-restore` (or `<pvc>-restore` per PVC) present, and **no** `ReplicationSource` for that same name

If replicas isn't 0, or a `ReplicationSource` is still there, the value path in step 3/4 is wrong — fix it and re-run before committing.

> The script needs `apps/.helmignore` to exclude `node_modules/` if any app directory (e.g. a Headlamp plugin under active development) has one checked out locally — Helm's chart loader errors on oversized files anywhere under `apps/`, not just files that would actually be templated. This also affects the plain `helm template apps -f apps/values.yaml --set cluster.name=<cluster>` command from CLAUDE.md. If you hit `Error: chart file "..." is larger than the maximum file size`, that's this — flag it to the user rather than deleting their local build artifacts.

## 6. Push, wait, confirm live

After merge, ArgoCD syncs within ~30s. Watch the restore:

```bash
kubectl -n <namespace> get replicationdestination <app>-restore -w
```

Done when `.status.lastSyncTime` is set and conditions show `Reconciled=True`. Also confirm the workload is actually at 0 replicas in the live cluster (`kubectl -n <namespace> get deploy/sts <app>`), not just in the render — ArgoCD's own reconciliation is the real source of truth once merged.

## 7. Roll back — same care, same verification, in reverse

Remove **both** the scale-down override and the `volsync.restore` block from `clusters/<cluster>/apps.yaml` in one commit (per CLAUDE.md). Re-run the same check before pushing:

```bash
.claude/skills/volsync-restore/scripts/render-check.sh <cluster> <app>
```

Confirm: the Deployment/StatefulSet is back to its normal (non-zero, or absent-from-output-meaning-default) replica count, a `ReplicationSource` is present again, and no `ReplicationDestination` remains.

Push, let ArgoCD sync, then confirm live: the `<app>-restore` `ReplicationDestination` object is gone (ArgoCD prunes it — `prune: true` is the default `syncPolicy`), the `ReplicationSource` exists and is scheduled per `volsync.backupSchedule` (default `0 2 * * *`), and the workload's pod count is back to normal.
