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
       └─► deploy
              │
              ├─► terraform apply ── Cloudflare DNS, NetBird policies/groups,
              │                      Infisical project structure, VolSync secret paths,
              │                      Vultr (mgmt cluster)
              │
              └─► omni sync ──────── cluster.yaml → Omni (Talos node config,
                                     k8s version, machine assignments)
```

### Path 2 — ArgoCD (pull-based, continuous)

```
Git (main)
    │  ▲ polls every 30s
    │  │
    ▼  │
ArgoCD (on each cluster)
    │
    ├── Source 1: clusters/<cluster>/   raw Kubernetes manifests
    │
    └── Source 2: apps/                 Helm chart → one ArgoCD Application per enabled app
                                                │
                                                └─► syncs apps/<name>/ charts to cluster
```

These two paths are independent. CI handles infrastructure and Talos cluster config; ArgoCD handles every Kubernetes workload. App-only changes (editing `app.yaml`, chart templates, values) are picked up by ArgoCD once merged into the `main` branch without any CI deploy step.

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
    │  remote-write (via NetBird)
    ▼
Prometheus Aggregator  ──  boa1-prod (metrics namespace)
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
# clusters/boa1-prod/apps.yaml, spec.sources[1].helm.values
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

| Type | Kind | Role |
|------|------|------|
| `mgmt` | DigitalOcean Kubernetes (DOKS) | Single management cluster. Hosts Omni, ArgoCD, Infisical operator, and shared infrastructure. Provisioned by DigitalOcean via Terraform. |
| `<region>-gw` | Talos (Omni-managed) | One per region. Gateway cluster for bare-metal provisioning and subnet routing. |
| `<region>-*` | Talos (Omni-managed) | General compute clusters for production workloads. |

Talos clusters have their node config, k8s version, and machine assignments managed entirely by Omni, which runs on the `mgmt` cluster. The CI deploy workflow syncs `clusters/<name>/cluster.yaml` to Omni on every merge to `main`.

See [Gateway clusters](networking.md#gateway-clusters) for how gateway clusters handle bare-metal provisioning and subnet routing.

## Sync wave order

[ArgoCD sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) control the ordering of app deployments on a cluster. Lower wave numbers sync first.

| Wave | Apps | Why first |
|------|------|-----------|
| -40 | `cilium` | CNI must be ready before any other pod can schedule |
| -35 | `infisical`, `multus` | Secrets operator must be ready so other apps can pull secrets; Multus for multi-homed pods |
| -30 | `cert-manager`, `argocd`, `rbac` | TLS, GitOps and access control |
| -25 | `generic-device-plugin-tun`, `node-inotify-limits` | Node resource registration and sysctl tuning before consumers |
| -20 | `netbird`, `cert-manager-crs`, `spegel`, `external-dns-crs` | Mesh access, certificate issuers, and DNS CRDs before services need them |
| -10 | `external-dns`, `netbird-crs`, `kubelet-serving-cert-approver` | DNS registration and network routing before apps |
| -5 | `volsync` | Backup operator ready before app PVCs need it |
| 0 | everything else | Default wave |
| 1+ | apps that depend on wave-0 apps | |

## CI/CD pipeline

Four reusable workflows are called from `.github/workflows/ci.yaml`: `scan`, `build`, `deploy`, and `mirror` (mirrors the repo to a public read-only remote on push; not covered further here).

### `scan` — security and lint

Runs on every PR and push:

- [`pre-commit`](https://pre-commit.com/) — YAML lint, trailing whitespace, detect-secrets, Helm lint
- PR title validation against [Conventional Commits](https://www.conventionalcommits.org/) (enforced by a regex check; only runs on PRs)
- [Trivy](https://trivy.dev/) — config scan for misconfigurations in Kubernetes manifests (table output in the job log; CRITICAL/HIGH findings fail the job)

### `build` — Docker images and docs

- Detects which `apps/*/` directories changed (on PRs); builds all on push to `main`
- Builds the `Dockerfile` if present, tags with both `<git-sha>` and `latest`, pushes to `ghcr.io/homescalecloud/<name>`
- Runs a Trivy vulnerability scan on each built image (CRITICAL/HIGH, blocks on failure)
- **Deploys this documentation site** to GitHub Pages (`mkdocs gh-deploy`) on every push to `main`

### `deploy` — infrastructure and cluster sync/bootstrap

Runs on every PR and push to `main` (after `scan` and `build` pass), serialized repo-wide via a `concurrency: deploy` group so overlapping runs queue instead of racing. It has three sequential jobs — `terraform` → `omni` → `ansible` (main only) — and each job independently joins the NetBird mesh with its own ephemeral setup key, revoked when that job ends (not one shared connection for the whole run).

#### 1. `terraform`

- **On PR**: runs `terraform plan` and posts the plan diff as a PR comment
- **On merge to `main`**: runs `terraform apply` (gated by a GitHub Environment) — manages Cloudflare DNS, Vultr, Infisical project structure, NetBird policies and groups, VolSync secret paths, etc

#### 2. `omni` (after terraform)

Detects changed `clusters/<name>/cluster.yaml` and `infra/omni/machineclasses/*.yaml` files. First checks that Omni is reachable (`REDACTED/healthz`) — if it isn't, the plan/sync steps are skipped entirely rather than failing.

- **On PR**: dry-runs each changed cluster template and machine class with `omnictl ... --dry-run`, posts results as PR comments
- **On merge to `main`**: runs `omnictl cluster template sync` for all clusters and `omnictl apply` for all machine classes

Shared Talos patches from `infra/omni/patches/` are applied alongside each cluster template.

#### 3. `ansible` (after omni, main only)

Runs two Ansible playbooks in sequence against the live clusters via NetBird:

- **`bootstrap-mgmt.yml`** — bootstraps the `mgmt` cluster specifically (reads its kubeconfig from Infisical)
- **`bootstrap-cluster.yml`** — ensures every cluster has its `cluster-secrets`, `cilium`, and `argocd` roles applied (idempotent)

---

ArgoCD picks up any Git changes and reconciles cluster state automatically — no deploy step is needed for app-only changes.
