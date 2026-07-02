# NetBirdNetworkResourceNotReady

**Severity:** Warning
**Alert:** `NetBirdNetworkResourceNotReady`
**Dashboard:** [NetBird Operator](https://REDACTED/d/netbird-operator)

## What this means

A `NetworkResource` object has not reported its `Ready` condition as `True` for 15 minutes. The backing Kubernetes `Service` it exposes is likely unreachable at its `REDACTED` NetBird DNS name, even if the Service and its pods are otherwise healthy. This is scoped to a single app/service rather than the whole cluster's mesh connectivity, hence warning rather than critical.

## Common causes

| Cause | Fix |
|---|---|
| Referenced `serviceRef` no longer exists | Confirm the Service named in the `NetworkResource` spec still exists in the same namespace |
| Referenced `networkRouterRef` not Ready | Check `NetBirdNetworkRouterNotReady` for the same cluster first — a router outage cascades to all its resources |
| NetBird operator reconcile failures | Check `NetBirdReconcileErrors` for `controller=networkresource` |
| DNS record ID collision or deleted out-of-band in NetBird | Check the NetBird management plane console for the record |

## Remediation

1. `kubectl --context <cluster> -n <namespace> get networkresource <name> -o yaml` — check `status.conditions` for the `reason`/`message` on the `Ready` condition.
2. Confirm the referenced Service exists and has endpoints: `kubectl --context <cluster> -n <namespace> get svc,endpoints <service-name>`.
3. Check whether the cluster's `NetworkRouter` is Ready (see [NetBirdNetworkRouterNotReady](netbird-networkrouter-not-ready.md)) — most `NetworkResource` failures are downstream of a router problem.
4. Check the NetBird operator's logs for reconcile errors tagged `controller=networkresource` and the specific resource name.
