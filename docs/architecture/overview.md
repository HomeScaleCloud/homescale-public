# Architecture Overview

HomeScale uses a full GitOps model: **this repository is the source of truth** for every cluster. Nothing is applied manually except the one-time bootstrap. All ongoing changes flow through a pull request.

## GitOps loop

```
┌─────────────┐    PR merged     ┌──────────────┐    Terraform apply   ┌───────────────────┐
│  Git (main) │ ───────────────► │  CI: deploy  │ ───────────────────► │ Cloud resources   │
└─────────────┘                  └──────────────┘                       │ (Cloudflare, NB…) │
       │                                │                               └───────────────────┘
       │                                │ Omni cluster template sync
       │                                ▼
       │                         ┌──────────────┐
       │                         │ Omni / Talos │  (cluster config, node assignments)
       │                         └──────────────┘
       │
       │  ArgoCD polls every 30 s
       ▼
┌─────────────────────────────────────────────────────┐
│  ArgoCD (on each cluster)                           │
│  ┌──────────────────────────┐                       │
│  │  app-of-apps (apps.yaml) │  two sources:         │
│  │  • clusters/<cluster>/   │  raw manifests        │
│  │  • apps/                 │  Helm → Applications  │
│  └──────────────────────────┘                       │
│              │ generates per-app ArgoCD Application  │
│              ▼                                       │
│  ┌──────────────────────────────────────────────┐   │
│  │  ArgoCD Application (one per enabled app)    │   │
│  │  → syncs apps/<name>/ Helm chart to cluster  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### App-of-apps pattern

Each cluster bootstraps with a single [ArgoCD app-of-apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern) (`clusters/<cluster>/apps.yaml`) applied manually once. That app has **two sources**:

1. **`clusters/<cluster>/`** — any raw Kubernetes manifests scoped to that cluster (e.g. cluster-specific CRs, Omni machine selectors)
2. **`apps/`** — the Helm chart that reads every `apps/*/app.yaml` and renders one [ArgoCD `Application`](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications) per enabled app

From that point on ArgoCD self-manages: changes to this repo are picked up automatically within the configured reconciliation interval (`timeout.reconciliation: 30s`).

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

| Cluster | Role |
|---------|------|
| `mgmt` | Runs ArgoCD, Infisical operator, and shared infrastructure components |
| `boa1-prod` | Production workloads for region `boa1` |
| `boa1-gw` | Gateway cluster for region `boa1`; bare-metal provisioning, subnet routing |

**Gateway clusters** (`*-gw`) have three distinct roles:

- **Bare-metal provisioning** — the `omni-infra-provider` app runs the [Omni infrastructure provider](https://omni.siderolabs.com/how-to-guides/install-and-configure-omni-integration-in-bare-metal-mode) to PXE-boot Talos nodes in the region
- **Subnet routing** — a NetBird subnet router exposes the region's BMC and MGMT subnets across the WireGuard mesh so they're reachable from `mgmt` and CI
- **Region ↔ mgmt connectivity** — bridges region-local services to the central `mgmt` cluster

## Sync wave order

[ArgoCD sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) control the ordering of app deployments on a cluster. Lower wave numbers sync first.

| Wave | Apps | Why first |
|------|------|-----------|
| -40 | `cilium` | CNI must be ready before any other pod can schedule |
| -35 | `infisical`, `multus` | Secrets operator must be ready so other apps can pull secrets; Multus for multi-homed pods |
| -30 | `cert-manager`, `argocd`, `rbac` | TLS infrastructure and access control before workloads |
| -25 | `generic-device-plugin` | Node resource registration before consumers |
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
- PR title validation against [Conventional Commits](https://www.conventionalcommits.org/) (enforced by gitlint)
- [CodeQL](https://codeql.github.com/) — static analysis
- [Trivy](https://trivy.dev/) — config scan for misconfigurations in Kubernetes manifests

### `build` — Docker images

- Detects which `apps/*/` directories changed (on PRs); builds all on push to `main`
- Builds the `Dockerfile` if present, pushes to `ghcr.io/homescalecloud/<name>`
- Runs a Trivy image scan on each built image
- Lints Helm charts (`helm lint`)

### `deploy` — infrastructure and cluster sync

Runs only on push to `main` (after `scan` and `build` pass):

1. Joins the NetBird mesh with an ephemeral one-time setup key so it can reach internal infrastructure
2. **Terraform plan/apply** — `infra/terraform/` manages Cloudflare DNS, DigitalOcean, Infisical project setup, NetBird configuration
3. **Omni cluster template sync** — for clusters whose `cluster.yaml` changed, pushes the updated template to Omni

ArgoCD then picks up any Git changes and reconciles cluster state automatically — no deploy step needed for app changes.
