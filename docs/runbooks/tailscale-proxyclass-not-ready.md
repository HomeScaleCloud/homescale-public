# TailscaleProxyClassNotReady

**Severity:** Warning
**Alert:** `TailscaleProxyClassNotReady`
**Dashboard:** [Tailscale Operator](https://REDACTED/d/tailscale-operator)

## What this means

The `default` `ProxyClass` (`tailscale` namespace) has not reported a `ProxyClassReady` condition for 15 minutes. Proxies referencing it (via `proxyConfig.defaultProxyClass`) may not pick up its configuration — currently this only controls per-proxy metrics (`spec.metrics.enable`/`serviceMonitor.enable`), so the practical impact is stale or missing proxy metrics, not loss of tailnet connectivity.

## Common causes

| Cause | Fix |
|---|---|
| Operator itself unhealthy | Check `TailscaleOperatorDown` first — a `ProxyClass` can't reconcile without a working operator |
| Invalid `ProxyClass` spec | `kubectl -n tailscale describe proxyclass default` and check `.status.conditions` for the specific validation error |

## Remediation

1. `kubectl -n tailscale get proxyclass default -o yaml` and check `.status.conditions` for the reason.
2. Check the operator's own logs for reconcile errors touching this `ProxyClass`.
3. If the spec was recently changed, confirm the new values are valid per the `ProxyClass` CRD schema.
