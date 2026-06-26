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
       │                             MkDocs → GitHub Pages (xxx)
       │
       └─► deploy
              │
              ├─► terraform apply ── Cloudflare DNS, NetBird policies/groups,
              │                      Infisical project structure, VolSync secret paths,
              │                      DigitalOcean (mgmt cluster)
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
    ├──► Grafana        dashboards at xxx
    ├──► Alertmanager   fires to #alerts-infra-plat Slack channel
    │                   alert title links to runbook
    └──► Loki           log aggregation from all clusters via Grafana Alloy
```

Prometheus on each cluster retains 2 hours of data and remote-writes everything to the central instance, which carries the `cluster` external label. Grafana, Alertmanager, and the aggregated Prometheus/Loki instances each run as a single instance on a designated prod cluster. See [alert runbooks](../runbooks/omni-down.md) for configured alerts.

## App catalog (`apps/`)

`apps/` is a Helm chart. `apps/templates/applications.yaml` loops over every `apps/*/app.yaml` using Helm `fileset` + `fromYaml` and generates an ArgoCD `Application` for each app that is enabled for the current cluster.

### Enabling / disabling apps per cluster

Each `app.yaml` has a `defaultDeploy` boolean and optional per-cluster overrides under `clusters.<name>`:

```yaml
defaultDeploy: false        # don't deploy everywhere by default
clusters:
  boa1-prod:
    deploy: true            # enable only on this cluster
    values:
      replicaCount: 3       # cluster-specific value override (deep-merged)
```

See the [App reference](../operations/apps.md) for the full field list.

### Apps built in CI

Any app directory that contains both a `Chart.yaml` and a `Dockerfile` is treated as a first-party image. CI builds it on every merge to `main` and pushes to `ghcr.io/homescalecloud/<name>`.

## Cluster topology

| Type | Kind | Role |
|------|------|------|
| `mgmt` | DigitalOcean Kubernetes (DOKS) | Single management cluster. Hosts Omni, ArgoCD, Infisical operator, and shared infrastructure. Provisioned by DigitalOcean via Terraform. |
| `<region>-gw` | Talos (Omni-managed) | One per region. Gateway cluster for bare-metal provisioning and subnet routing. |
| `<region>-prod` | Talos (Omni-managed) | One per region. General compute cluster for production workloads. |

Talos clusters have their node config, k8s version, and machine assignments managed entirely by Omni, which runs on the management cluster. The CI deploy workflow syncs `clusters/<name>/cluster.yaml` to Omni on every merge to `main`.

**Gateway clusters** (`<region>-gw`) — one per region — have three distinct roles:

- **Bare-metal provisioning** — the `omni-infra-provider` app runs the Omni infrastructure provider to PXE-boot Talos nodes in the region
- **Subnet routing** — a NetBird subnet router exposes the region's BMC and MGMT subnets across the WireGuard mesh so they're reachable from the management cluster and CI
- **Region ↔ management connectivity** — bridges region-local services to the central management cluster

## Sync wave order

[ArgoCD sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) control the ordering of app deployments on a cluster. Lower wave numbers sync first.

| Wave | Apps | Why first |
|------|------|-----------|
| -40 | `cilium` | CNI must be ready before any other pod can schedule |
| -35 | `infisical`, `multus` | Secrets operator must be ready so other apps can pull secrets; Multus for multi-homed pods |
| -30 | `cert-manager`, `argocd`, `rbac` | TLS infrastructure and access control before workloads |
| -25 | `generic-device-plugin-tun` | Node resource registration before consumers |
| -20 | `netbird`, `cert-manager-crs`, `spegel` | Mesh access and certificate issuers before services need them |
| -10 | `external-dns`, `netbird-crs`, `kubelet-serving-cert-approver` | DNS registration and network routing before apps |
| -5 | `volsync` | Backup operator ready before app PVCs need it |
| 0 | everything else | Default wave |
| 1+ | apps that depend on wave-0 apps | |

## CI/CD pipeline

Three reusable workflows are called from `.github/workflows/ci.yaml`:

### `scan` — security and lint

Runs on every PR and push:

- [`pre-commit`](https://pre-commit.com/) — YAML lint, trailing whitespace, detect-secrets, Helm lint
- PR title validation against [Conventional Commits](https://www.conventionalcommits.org/) (enforced by a regex check; only runs on PRs)
- [CodeQL](https://codeql.github.com/) — static analysis of GitHub Actions workflow files
- [Trivy](https://trivy.dev/) — config scan for misconfigurations in Kubernetes manifests (results uploaded to GitHub Security)

### `build` — Docker images and docs

- Detects which `apps/*/` directories changed (on PRs); builds all on push to `main`
- Builds the `Dockerfile` if present, tags with both `<git-sha>` and `latest`, pushes to `ghcr.io/homescalecloud/<name>`
- Runs a Trivy vulnerability scan on each built image (CRITICAL/HIGH, blocks on failure)
- Lints all Helm charts under `apps/`
- **Deploys this documentation site** to GitHub Pages (`mkdocs gh-deploy`) on every push to `main`

### `deploy` — infrastructure and cluster sync

Runs on every PR and push to `main` (after `scan` and `build` pass). CI connects to internal infrastructure by joining the NetBird mesh with an ephemeral setup key that is revoked at the end of the run. It has three sequential jobs:

#### 1. `terraform`

- **On PR**: runs `terraform plan` and posts the plan diff as a PR comment
- **On merge to `main`**: runs `terraform apply` — manages Cloudflare DNS, DigitalOcean, Infisical project structure, NetBird policies and groups, VolSync secret paths

#### 2. `omni` (after terraform)

Detects changed `clusters/<name>/cluster.yaml` and `infra/omni/machineclasses/*.yaml` files.

- **On PR**: dry-runs each changed cluster template and machine class with `omnictl ... --dry-run`, posts results as PR comments
- **On merge to `main`**: runs `omnictl cluster template sync` for all clusters and `omnictl apply` for all machine classes

Shared Talos patches from `infra/omni/patches/` are applied alongside each cluster template.

#### 3. `ansible` (after omni, main only)

Runs two Ansible playbooks against the live clusters via NetBird:

- **`bootstrap-infra-providers.yml`** — creates Omni service accounts for the `omni-infra-provider` app on each gateway cluster
- **`bootstrap-cluster.yml`** — ensures ArgoCD is bootstrapped on every cluster (idempotent)

---

ArgoCD picks up any Git changes and reconciles cluster state automatically — no deploy step is needed for app-only changes.
