# NetBirdNetworkRouterNotReady

**Severity:** Critical
**Alert:** `NetBirdNetworkRouterNotReady`
**Dashboard:** [NetBird Operator](https://REDACTED/d/netbird-operator)

## What this means

A `NetworkRouter` object (one per cluster, in the `netbird` namespace) has not reported its `Ready` condition as `True` for 10 minutes. New `NetworkResource` registrations routed through this router will not resolve in the cluster's `<cluster>REDACTED` DNS zone, and existing registrations may fall out of sync — internal service exposure across the mesh for that cluster is impaired.

## Common causes

| Cause | Fix |
|---|---|
| `networkrouter-<cluster>` pods not running | `kubectl --context <cluster> -n netbird get pods -l app.kubernetes.io/name=networkrouter` |
| Referenced `dnsZoneRef` missing or renamed | Confirm the `<cluster>REDACTED` DNS zone still exists in the NetBird management plane |
| NetBird operator reconcile failures | Check `NetBirdOperatorDown` / `NetBirdReconcileErrors` for `controller=networkrouter` first |
| NetBird management API outage | Check NetBird status; this is out of our control |

## Remediation

1. `kubectl --context <cluster> get networkrouter -n netbird <cluster> -o yaml` — check `status.conditions` for the `reason`/`message` on the `Ready` condition.
2. `kubectl --context <cluster> -n netbird get pods -l app.kubernetes.io/name=networkrouter` and check logs for the router pods.
3. Check the NetBird operator's logs on the same cluster for reconcile errors tagged `controller=networkrouter`.
4. Once Ready, confirm DNS resolution recovers by resolving a known `NetworkResource` FQDN (e.g. `grafana.metrics.<cluster>REDACTED`) from a machine on the mesh.
