# TailscaleProxyGroupNotReady

**Severity:** Critical
**Alert:** `TailscaleProxyGroupNotReady`
**Dashboard:** [Tailscale Operator](https://REDACTED/d/tailscale-operator)

## What this means

The `ingress` `ProxyGroup` (`tailscale` namespace) has not reported a `ProxyGroupReady` condition for 10 minutes. Services annotated `tailscale.com/proxy-group: ingress` to route through it may not be reachable over the tailnet — that's every exposed app Service. (Outbound-only access, e.g. `headlamp`/`metrics`'s cross-cluster targets, uses dedicated per-Service egress proxies instead, not this `ProxyGroup` — see [Networking](../architecture/networking.md#internal-service-exposure).)

## Common causes

| Cause | Fix |
|---|---|
| Proxy pods crash-looping or stuck pending | `kubectl -n tailscale get pods` (proxy StatefulSet pods are named after the ProxyGroup, e.g. `ingress-0`) and check logs/events/scheduling |
| Operator itself unhealthy | Check `TailscaleOperatorDown` first — a `ProxyGroup` can't reconcile without a working operator |
| Tag not permitted | Proxy pod logs will show tag errors if the ProxyGroup's `tags:` aren't owned correctly in the tailnet ACL |

## Remediation

1. `kubectl -n tailscale get proxygroup` and check `.status.conditions` for the specific reason.
2. `kubectl -n tailscale get pods` (proxy StatefulSet pods are named after the ProxyGroup, e.g. `ingress-0`) — confirm replicas are `Running`.
3. `kubectl -n tailscale logs <proxy-pod>` for the underlying error.
4. If pods are healthy but the condition is still stale, check the operator's own logs for reconcile errors touching this `ProxyGroup`.
