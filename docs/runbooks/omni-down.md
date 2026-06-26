# OmniDown

**Severity:** Critical
**Alert:** `OmniDown`
**Dashboard:** [Omni](https://xxx/d/omni)

## What this means

The Prometheus scrape target for the Omni pod in the `omni` namespace on the `mgmt` cluster has been returning failures for 5 minutes. While the pod may still be running, its metrics endpoint (`/metrics` on port 2122) is not responding.

Cluster provisioning, machine management, kubeconfig access, and `omnictl` operations are unavailable until Omni is restored.

## Diagnosis

```bash
# Check pod status
kubectl -n omni get pods

# Check recent events
kubectl -n omni describe pod -l app.kubernetes.io/name=omni

# Check logs
kubectl -n omni logs -l app.kubernetes.io/name=omni --tail=100

# Check the health endpoint directly
kubectl -n omni exec -it deploy/omni -- curl -sk https://localhost/healthz
```

Omni exposes `/healthz` on its HTTPS port and `/metrics` on port 2122. If the pod is `Running` but health checks are failing, it may be stuck in an error state (e.g., embedded etcd issue, storage problem, TLS misconfiguration).

## Common causes

| Cause | Signs | Fix |
|---|---|---|
| Pod crash-looping | `CrashLoopBackOff` in `kubectl get pods` | Check logs for the root cause; restart if transient |
| PVC full or unavailable | Storage errors in logs | Check `omni_sqlite_db_size_bytes` and Longhorn volume health |
| etcd corruption | `etcd` errors in logs | May require restore from VolSync backup — see [Backups](../operations/backups.md) |
| TLS cert expired | TLS handshake errors | Renew cert-manager certificate for `omni-tls` |
| SideroLink WireGuard failure | WireGuard errors at startup | Restart pod; check `xxx` DNS resolution |

## Restore from backup

If Omni's storage is corrupted and needs to be restored, follow the [VolSync restore procedure](../operations/backups.md) for the `omni` app.
