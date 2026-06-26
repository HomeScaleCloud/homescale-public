# OmniDown

**Severity:** Critical
**Alert:** `OmniDown`
**Dashboard:** [Omni](https://xxx/d/omni)

## What this means

The Prometheus scrape target for the Omni pod in the `omni` namespace on the `mgmt` cluster has been returning failures for 5 minutes. While the pod may still be running, its metrics endpoint (`/metrics` on port 2122) is not responding.

Cluster provisioning, machine management, kubeconfig access, and `omnictl` operations are unavailable until Omni is restored.

## Common causes

| Cause | Fix |
|---|---|
| Pod crash-looping | Check logs for the root cause; restart if transient |
| PVC full or unavailable | Check `omni_sqlite_db_size_bytes` in Grafana and Longhorn volume health |
| etcd corruption | May require restore from VolSync backup — see [Backups](../operations/backups.md) |
| TLS cert expired | Renew the cert-manager certificate for `omni-tls` |
| SideroLink WireGuard failure at startup | Restart pod; check `xxx` DNS resolution |

## Restore from backup

If Omni's storage is corrupted and needs to be restored, follow the [VolSync restore procedure](../operations/backups.md) for the `omni` app.
