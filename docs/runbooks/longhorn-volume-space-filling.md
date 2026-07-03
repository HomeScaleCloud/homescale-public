# LonghornVolumeSpaceFilling

**Severity:** Warning
**Alert:** `LonghornVolumeSpaceFilling`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

The Longhorn volume backing PVC `$labels.pvc_namespace`/`$labels.pvc` has used over 90% of its provisioned capacity. Once full, writes from the owning application will start failing.

## Common causes

| Cause | Fix |
|---|---|
| Application data growth outpacing the PVC's provisioned size | Expand the PVC (if the app's StorageClass allows volume expansion) or clean up stale data |
| Log files or caches filling the volume | Check the pod's filesystem usage (`kubectl exec` + `du`) for reclaimable space |
| Snapshot/backup retention holding old data on the volume | Check whether the app has its own internal retention policy separate from VolSync's restic retention |

## Remediation

1. Confirm current usage on the [Longhorn Monitoring dashboard](https://REDACTED/d/ozk-lh-mon) or `kubectl -n longhorn-system get volumes.longhorn.io <volume> -o jsonpath='{.status.actualSize}'`.
2. If the app can tolerate it, clean up unnecessary data from within the pod.
3. Otherwise, expand the PVC: edit the PVC's `spec.resources.requests.storage` to a larger value (Longhorn's default StorageClass has `allowVolumeExpansion: true`) and merge to `main`.
4. After expansion, confirm the filesystem inside the pod was resized (Longhorn's CSI driver resizes online for most filesystem types; some workloads need a restart to pick it up).
