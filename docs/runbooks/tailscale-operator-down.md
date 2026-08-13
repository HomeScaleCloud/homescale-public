# TailscaleOperatorDown

**Severity:** Critical
**Alert:** `TailscaleOperatorDown`
**Dashboard:** [Tailscale Operator](https://REDACTED/d/tailscale-operator)

## What this means

The Tailscale operator Deployment (`operator`, `tailscale` namespace) has had zero available replicas for 5 minutes. `ProxyGroup`/`ProxyClass` objects on this cluster will stop reconciling — new or changed tailnet exposure, tagging, and DNS registration will not take effect until the operator recovers.

## Common causes

| Cause | Fix |
|---|---|
| Operator pod crash-looping | `kubectl -n tailscale get pods -l app=operator` and check logs/events |
| OAuth credentials invalid or not yet synced | Operator logs will show auth errors reading `/oauth/client_id`/`/oauth/client_secret`; check the `operator-oauth` secret in the `tailscale` namespace and the `InfisicalSecret` syncing it |
| Requested tags not permitted | Operator logs will show "requested tags ... invalid or not permitted"; confirm the tailnet ACL's `tagOwners` grants the operator's own tag ownership of what it's trying to apply |

## Remediation

1. `kubectl -n tailscale get pods -l app=operator` — confirm the pod is `Running` and not restarting.
2. `kubectl -n tailscale logs deploy/operator -f` for crash reasons or repeated auth errors.
3. `kubectl -n tailscale get secret operator-oauth` and confirm it exists with `client_id`/`client_secret` keys populated.
4. Once the operator is back up, existing `ProxyGroup`/`ProxyClass` objects reconcile automatically on their next resync — no manual re-trigger is needed.
