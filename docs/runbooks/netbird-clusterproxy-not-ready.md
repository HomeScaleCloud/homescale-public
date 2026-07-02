# NetBirdClusterProxyNotReady

**Severity:** Critical
**Alert:** `NetBirdClusterProxyNotReady`
**Dashboard:** [NetBird Operator](https://REDACTED/d/netbird-operator)

## What this means

A `ClusterProxy` object (one per cluster, in the `netbird` namespace) has not reported its `Ready` condition as `True` for 10 minutes. The cluster's routing peer into the NetBird mesh may be down, which breaks access to that cluster's Kubernetes API server for anyone/anything in the `k8s` or `cluster-<name>` NetBird groups — including CI's ephemeral NetBird access for Terraform/Omni operations.

## Common causes

| Cause | Fix |
|---|---|
| `clusterproxy-<cluster>` pods not running | `kubectl --context <cluster> -n netbird get pods -l app.kubernetes.io/name=clusterproxy` |
| NetBird management API unreachable from the operator | Check `NetBirdOperatorDown`/operator logs on the same cluster first |
| Stale `serviceAccountName` reference in the `ClusterProxy` spec | Confirm `netbird-clusterproxy` ServiceAccount still exists in the `netbird` namespace |
| NetBird management plane outage (external, api.netbird.io) | Check NetBird status; this is out of our control |

## Remediation

1. `kubectl --context <cluster> get clusterproxy -n netbird <cluster> -o yaml` — check `status.conditions` for the `reason`/`message` on the `Ready` condition.
2. `kubectl --context <cluster> -n netbird get pods -l app.kubernetes.io/name=clusterproxy` and check logs for the proxy pods themselves.
3. Check the NetBird operator's own logs on the same cluster (`kubectl --context <cluster> -n netbird logs deploy/netbird-netbird-operator`) for reconcile errors tagged `controller=clusterproxy`.
4. If the NetBird management API itself is down, this will self-resolve once it recovers — the operator retries automatically.
