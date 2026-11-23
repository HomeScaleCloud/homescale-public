# Architecture Overview

HomeScale uses a full GitOps model: **this repository is the source of truth** for every cluster. Nothing is applied manually except the one-time bootstrap. All ongoing changes flow through pushes to the `main` branch.

## GitOps loop

There are two independent reconciliation paths from `main`:

### Path 1 — CI (push-based, triggered on merge)

```
PR merged to main
       │
       ├─► scan ──────────────────── YAML lint, secrets scan, CodeQL, Trivy
       │
       ├─► build ─────────────────── Docker images → ghcr.io/homescalecloud/<name>
       │                             MkDocs → GitHub Pages (REDACTED)
       │
       └─► test ──────────────────── hsctl/TOPF/bootstrap/update-cluster test suites
```

External infrastructure (`infra/tofu/`) and Talos/Kubernetes reconciliation are **not** triggered by this CI pipeline at all — see "CI/CD pipeline" below.

### Path 2 — ArgoCD (pull-based, continuous)

```
Git (main)
    │  ▲ polls every 30s
    │  │
    ▼  │
ArgoCD (on each cluster)
    │
    ├── Source 1: clusters/<cluster>/       recursive manifests; exclude topf.yaml
    │
    └── Source 2: apps/                 Helm chart → one ArgoCD Application per enabled app
                                                │
                                                └─► syncs apps/<name>/ charts to cluster
```

These two paths are independent. CI (`scan`/`build`/`test`) validates and publishes; external infrastructure is reconciled separately by Terrakube (webhook-triggered on push/PR, not CI — see below) and Talos/Kubernetes reconciliation is a manually dispatched Ansible run (see [Clusters](clusters.md)); ArgoCD handles every Kubernetes workload. App-only changes (editing `values.yaml`, `Chart.yaml` annotations, chart templates) are picked up by ArgoCD once merged into the `main` branch without any CI deploy step.

## Secrets

```
Infisical (SaaS)
    │
    │  Infisical k8s operator (syncWave -35)
    │  watches InfisicalSecret CRs in each namespace
    ▼
Kubernetes Secrets  ──►  consumed by app pods as env vars / mounted files
```

Each app that needs secrets defines an `InfisicalSecret` CR in its Helm chart pointing at a path in Infisical (e.g. `/k8s/<namespace>/<app>`). The operator syncs them into the cluster at runtime — no secrets are stored in this repo. See [Secrets](secrets.md) for details.

## Observability

```
Every cluster
    │  kube-prometheus-stack (per-cluster)
    │  scrapes: node-exporter, kube-state-metrics, app ServiceMonitors
    │
    │  remote-write (via Tailscale)
    ▼
Prometheus Aggregator  ──  production (metrics namespace)
    │
    ├──► Grafana        dashboards at REDACTED
    ├──► Alertmanager   fires to #alerts-infra-plat Slack channel
    │                   alert title links to runbook
    └──► Loki           log aggregation from all clusters via Grafana Alloy
```

Prometheus on each cluster retains 2 hours of data and remote-writes everything to the central instance, which carries the `cluster` external label. Grafana, Alertmanager, and the aggregated Prometheus/Loki instances each run as a single instance on a designated prod cluster. See [alert runbooks](../runbooks/index.md) for configured alerts.

## App catalog (`apps/`)

`apps/` is a Helm chart. `apps/templates/applications.yaml` loops over every `apps/*/app.yaml` using Helm `fileset` + `fromYaml` and generates an ArgoCD `Application` for each app that is enabled for the current cluster.

### Enabling / disabling apps per cluster

Each `app.yaml` has a `defaultDeploy` boolean. Deployment overrides live separately, in `clusters/<cluster>/apps.yaml`'s inline Helm values, under an `apps:` map keyed by app name:

```yaml
# apps/my-app/app.yaml
defaultDeploy: false        # don't deploy everywhere by default
```

```yaml
# clusters/production/apps.yaml, spec.sources[1].helm.values
apps:
  my-app:
    deploy: true            # enable only on this cluster
    values:
      replicaCount: 3       # deployment override (deep-merged)
```

See the [App reference](apps.md) for the full field list.

### Apps built in CI

Any app directory that contains both a `Chart.yaml` and a `Dockerfile` is treated as a first-party image. CI builds it on every merge to `main` and pushes to `ghcr.io/homescalecloud/<name>`.

## Cluster topology

| Cluster | Kind | Role |
|---------|------|------|
| `production` | Talos (TOPF-managed) | Primary cluster — general compute, production workloads. |
| `development` | Talos (TOPF-managed) | Lab/development cluster. |

There is no separate management cluster. Each cluster self-hosts ArgoCD. TOPF reads permanent node inventory from `clusters/<cluster>/topf.yaml` and shared native patches from infra/topf. Ansible orders first bootstrap from the LAN; Terrakube manages external services via `infra/tofu/`. See [Clusters](clusters.md).

## Sync wave order

[ArgoCD sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) control the ordering of app deployments on a cluster. Lower wave numbers sync first.

| Wave | Apps | Why first |
|------|------|-----------|
| -40 | `cilium` | CNI must be ready before any other pod can schedule |
| -35 | `infisical`, `multus` | Secrets operator must be ready so other apps can pull secrets; Multus for multi-homed pods |
| -30 | `cert-manager`, `argocd`, `rbac` | TLS, GitOps and access control |
| -25 | `generic-device-plugin-tun`, `node-inotify-limits` | Node resource registration and sysctl tuning before consumers |
| -20 | `tailscale`, `spegel` | Mesh access and network routing before services need them |
| -10 | `external-dns`, `kubelet-serving-cert-approver` | DNS registration before apps |
| -5 | `volsync` | Backup operator ready before app PVCs need it |
| 0 | everything else | Default wave |
| 1+ | apps that depend on wave-0 apps | |

## CI/CD pipeline

Four reusable workflows are called from `.github/workflows/ci.yaml`: `scan`, `build`, `test`, and `mirror` (mirrors the repo to a public read-only remote on push; not covered further here).

`ci.yaml` runs on every PR and every push to `main`, and also on a published GitHub release. A release run executes `build` only (to rebuild every app image).

### `scan` — security and lint

Runs on every PR and push:

- [`pre-commit`](https://pre-commit.com/) — YAML lint, trailing whitespace, detect-secrets, Helm lint
- PR title validation against [Conventional Commits](https://www.conventionalcommits.org/) (enforced by a regex check; only runs on PRs)
- [Trivy](https://trivy.dev/) — config scan for misconfigurations in Kubernetes manifests (table output in the job log; CRITICAL/HIGH findings fail the job)

### `build` — Docker images and docs

- Builds only the `apps/*/` directories that changed — on PRs (versus the base branch) and on pushes to `main` (versus the previous commit). A published GitHub release rebuilds every app.
- Builds the `Dockerfile` if present, tags with both `<git-sha>` and `latest`, pushes to `ghcr.io/homescalecloud/<name>`
- Runs a Trivy vulnerability scan on each built image (CRITICAL/HIGH, blocks on failure)
- **Deploys this documentation site** to GitHub Pages (`mkdocs gh-deploy`) on every push to `main`

### `test` — Python test suites

Runs the `hsctl`/TOPF/bootstrap/update-cluster pytest suites (`test_hsctl.py`, `test_talos.py`, `test_bootstrap_cluster.py`, `test_update_cluster.py`) as a shared matrix job, each retaining its own check name.

### External infrastructure — Terrakube, not CI

`infra/tofu/` is **not** reconciled by `ci.yaml` at all. Each module (`tokenmaster`, `tunneler`, `pathfinder`, `recorder`, `puppeteer`) is its own self-hosted Terrakube VCS-backed workspace with its own GitHub-webhook-triggered run: `PUSH` to `main` runs `Plan and apply`; `PULL_REQUEST` runs `Plan` and posts the result as a PR comment. There is no CI- or `hsctl`-driven terraform/tofu apply any more. See "Infrastructure (`infra/`)" in `CLAUDE.md` for the full module/workspace breakdown.

### Talos/Kubernetes reconciliation — manual Ansible dispatch

`.github/workflows/deploy.yaml-disabled` holds a single `ansible` job that runs `bootstrap-cluster`, `update-cluster`, or other `infra/ansible/playbooks/` playbooks — it's disabled (renamed out of `.yaml`, so GitHub doesn't register it as a workflow) and not referenced from `ci.yaml`.

`update-cluster` reconciles Talos/Kubernetes versions, TOPF configuration, and service credentials for all bootstrapped clusters: native TOPF Talos upgrade, native talosctl Kubernetes upgrade, then ordinary config apply after version convergence. Clusters run serially, `development` before `production`, and failures stop the run. It requires `data.bootstrapComplete: true` and never creates secrets or bootstraps a fresh cluster. `bootstrap-cluster` performs initial setup and skips clusters already marked `bootstrapComplete`. See [hsctl](../operations/hsctl.md) and [Registering new machines](../operations/registering-machines.md).

ArgoCD continuously reconciles workloads after merge. App-only changes need neither Terrakube nor a TOPF apply.

## Checks and CI helpers

Everything under `tests/` is a check, not a deployment entrypoint. CI calls the same commands that can be run locally:

| Script | Purpose |
|--------|---------|
| test_manifests.sh | Render app charts and validate Kubernetes schemas, including recursive cluster manifests |
| test_runbooks.sh | Check that repository alerts link to existing runbooks |
| test_talos.py | Checks TOPF-rendered Talos configs against each cluster's `topf.yaml` |
| test_bootstrap_cluster.py | Checks Talos CA/secrets recovery and `bootstrap-cluster.yml` sequencing |
| test_update_cluster.py | Checks `update-cluster.yml`'s version-upgrade and credential-rotation logic |
| test_hsctl.py | Checks `hsctl get` output and cluster discovery |

The four `test_*.py` suites are pytest-based (`pip install pytest ansible-core PyYAML`); see "Key Commands" in `CLAUDE.md` for the full local invocation.

Terrakube PR runs post the plan as a PR comment. There is no separate topology-map generator or unused Helm build matrix. ArgoCD owns app reconciliation; TOPF owns Talos configuration; Ansible orders initial bootstrap; Terrakube owns external services.
