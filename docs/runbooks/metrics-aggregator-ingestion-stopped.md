# MetricsAggregatorIngestionStopped

**Severity:** Critical
**Alert:** `MetricsAggregatorIngestionStopped`
**Dashboard:** [Prometheus](https://REDACTED/d/k8s_addons_prometheus)

## What this means

The aggregator Prometheus instance has not received a single remote-write sample from *any* cluster for 15 minutes. Since every cluster remote-writes independently over its own Tailscale egress path, a simultaneous loss from all of them points at the aggregator side rather than any one cluster: the remote-write receiver itself, its storage, or a shared piece of networking.

## Common causes

| Cause | Fix |
|---|---|
| Aggregator Prometheus pod crash-looping or OOMKilled | `kubectl -n metrics get pods -l app.kubernetes.io/name=prometheus,operator.prometheus.io/name=aggregator` and check logs/events |
| PVC full | Check `prometheus_tsdb_storage_blocks_bytes` / volume usage against the 100Gi claim; consider lowering `retention` in `apps/metrics-aggr/templates/prometheus.yaml` |
| `enableRemoteWriteReceiver` disabled or Service/Ingress misconfigured | Confirm `apps/metrics-aggr/templates/prometheus.yaml` still sets `enableRemoteWriteReceiver: true` and the `prometheus` Service in the `metrics` namespace has endpoints |
| Tailscale mesh issue on the sending cluster | Check the `tailscale` app's ingress `ProxyGroup` health on `boa1-prod`, and the sending cluster's dedicated egress proxy pod for the `metrics-<cluster>-egress` `ExternalName` Service (`kubectl -n tailscale get pods -l tailscale.com/parent-resource=metrics-<cluster>-egress`, hostname `metrics-<cluster>-egress` in the tailnet admin console) |
| Aggregator cluster (currently `boa1-prod`) itself down or partitioned | Check node and cluster health directly |
