# OmniNoMachines

**Severity:** Critical
**Alert:** `OmniNoMachines`
**Dashboard:** [Omni](https://REDACTED/d/omni)

## What this means

`omni_machines` has been 0 for 5 minutes. Omni is up and scraping successfully, but reports no registered machines at all. This is an abnormal state — under normal operation this value should never be 0 once machines have been registered.

Possible causes:
- Omni's SQLite database or PVC was wiped or replaced with an empty one
- The PVC was accidentally recreated (e.g., an ArgoCD sync deleted and recreated the PVC)
- A VolSync restore was applied with an empty or wrong snapshot

!!! danger
    If this alert fires alongside `OmniDown`, investigate storage first — a corrupted database may cause Omni to start in a degraded state with no records visible.

## Diagnosis

```bash
# Confirm current machine count via Omni API (requires omnictl configured)
omnictl get machine

# Check the PVC
kubectl -n omni get pvc

# Check Omni's data directory size (via the toolbox sidecar)
kubectl -n omni exec -it deploy/omni -c toolbox -- du -sh /data/

# Check SQLite DB size
kubectl -n omni exec -it deploy/omni -c toolbox -- ls -lh /data/omni.db
```

If the database is empty (a few KB instead of hundreds of MB or more), data was lost.

## Recovery

If data was lost, restore from the most recent VolSync backup. Follow the [VolSync restore procedure](../operations/backups.md) for the `omni` app.

After restore:
1. Confirm `omni_machines` recovers to the expected count
2. Check `omni_connected_machines` — machines may take a few minutes to re-establish SideroLink connections
3. Verify cluster health with `omnictl get cluster` and `omnictl get clustermachine`

!!! warning
    After a full restore, machines need to re-establish WireGuard sessions with Omni. This happens automatically and typically completes within 5 minutes, but existing cluster workloads are unaffected during this period.
