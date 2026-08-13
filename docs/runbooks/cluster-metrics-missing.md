# ClusterMetricsMissing

**Severity:** Critical
**Alert:** `ClusterMetricsMissing`
**Dashboard:** [Prometheus](https://REDACTED/d/k8s_addons_prometheus)

## What this means

The aggregator Prometheus instance has not received any remote-written samples from the `cluster` named in the alert for at least 10 minutes, even though at least one other cluster is still reporting normally. Since other clusters are unaffected, this points at that specific cluster's local Prometheus instance or its Tailscale path to the aggregator, not the aggregator itself.

The affected cluster goes blind to dashboards and alerting until this recovers.

## Common causes

| Cause | Fix |
|---|---|
| Local Prometheus pod on the affected cluster wedged or crash-looping | `kubectl --context <cluster> -n metrics get pods -l app.kubernetes.io/name=prometheus` and check logs; restart if wedged |
| Cluster itself down or partitioned | Check node, networking and cluster health directly for that cluster |
