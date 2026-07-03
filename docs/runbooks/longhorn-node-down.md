# LonghornNodeDown

**Severity:** Critical
**Alert:** `LonghornNodeDown`
**Dashboard:** [Longhorn Monitoring](https://REDACTED/d/ozk-lh-mon)

## What this means

One or more nodes registered with Longhorn are no longer reporting `ready` status — the alert value is the count of missing nodes. This is a cluster-wide count, distinct from [LonghornNodeNotReady](longhorn-node-not-ready.md) which fires per specific node. Any replicas on the missing node(s) are unreachable, reducing redundancy for the volumes that use them.

## Common causes

| Cause | Fix |
|---|---|
| Node is powered off, network-partitioned, or crashed | Check node power/console via the PDU/BMC path for that node's rack; see the [PDU runbooks](apc-pdu-offline.md) if power-related |
| Kubelet or longhorn-manager pod on the node stopped reporting | `kubectl get nodes` and `kubectl -n longhorn-system get pods -o wide` to see if the node is `NotReady` at the k8s level too |
| Node was intentionally drained/removed but not yet removed from Longhorn | Remove the stale node entry from Longhorn (UI → Node → Delete) once confirmed permanently gone |

## Remediation

1. `kubectl get nodes -o wide` — confirm which node(s) are down at the Kubernetes level.
2. If it's a hardware/power issue, follow standard node recovery (power cycle via BMC, check physical connectivity).
3. Once the node rejoins, Longhorn reconciles automatically — replicas on that node resume, and Longhorn schedules replacement replicas elsewhere for any volumes that dropped below their replica count in the meantime.
4. If the node is permanently gone, remove it from Longhorn and from the cluster so replica scheduling doesn't keep targeting it.
