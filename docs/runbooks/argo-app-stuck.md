# ArgoAppStuck

**Severity:** Warning
**Alert:** `ArgoAppStuck`
**Dashboard:** [ArgoCD Overview](https://REDACTED/d/qPkgGHg7k)

## What this means

The same ArgoCD application has reported a `health_status` other than `Healthy` (e.g. `Progressing`, `Suspended`, `Missing`, `Degraded`, or `Unknown`) on 2 or more distinct clusters simultaneously, for 15 minutes.

A single cluster failing could be that cluster's environment (a down node, a local storage issue, etc.) — those individual instances are already covered by ArgoCD's own per-app Slack notifications. The same app failing the same way across multiple independent clusters at once points instead to something wrong with the app itself: a bad image tag, a broken manifest/chart change, or a config value that doesn't work anywhere.

## Common causes

| Cause | Fix |
|---|---|
| Recently changed image tag is broken/crash-looping everywhere | Check pod logs; roll back the image tag in `app.yaml` |
| Chart or manifest change introduced a bad resource (bad probe, bad env var, etc.) | Diff the last merged change to `apps/<name>/` and revert or fix |
| App depends on a shared value that's now wrong for every cluster (e.g. `{{ .Values.cluster.name }}` templating bug) | Check the rendered manifests via `helm template` for the affected clusters |
| Upstream chart dependency bump introduced a breaking change | Check `Chart.yaml` diff for subchart version bumps |
| Secret dependency expired/changed | Check any referneced secrets/tokens are present and valid in [Infisical](https://app.infisical.com) |
| App manifests reference a CRD that isn't installed yet on any cluster | Check sync wave ordering in `app.yaml` |

## Find the app

```bash
argocd app get <app-name>
```

or using the [dashboard](https://REDACTED/d/qPkgGHg7k).
