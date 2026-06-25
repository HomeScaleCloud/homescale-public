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

1. **`clusters/<cluster>/`** — any raw Kubernetes manifests scoped to that cluster (e.g. cluster-scoped RBAC, namespace labels, custom CRs). `cluster.yaml` is excluded from this source.
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
| `mgmt` | DigitalOcean-managed cluster that hosts Omni, ArgoCD, Infisical operator, and shared infrastructure |
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

Runs on every PR and push to `main` (after `scan` and `build` pass). It has three sequential jobs:

#### 1. `terraform`

Connects to NetBird (ephemeral setup key), then:

- **On PR**: runs `terraform plan` and posts the plan diff as a PR comment
- **On merge to `main`**: runs `terraform apply` — manages Cloudflare DNS, DigitalOcean, Infisical project structure, NetBird policies and groups

#### 2. `omni` (after terraform)

Detects changed `clusters/<name>/cluster.yaml` and `infra/omni/machineclasses/*.yaml` files. On PRs, only changed files are processed; on push to `main`, all clusters and machine classes are synced.

- **On PR**: dry-runs each changed cluster template and machine class with `omnictl ... --dry-run`, posts results as PR comments
- **On merge to `main`**: runs `omnictl cluster template sync` for all clusters and `omnictl apply` for all machine classes

Shared Talos patches from `infra/omni/patches/` are applied alongside each cluster template.

#### 3. `ansible` (after omni, main only)

Runs two Ansible playbooks against the live clusters via NetBird:

- **`bootstrap-infra-providers.yml`** — creates Omni service accounts for the `omni-infra-provider` app on each gateway cluster
- **`bootstrap-cluster.yml`** — ensures ArgoCD is bootstrapped on every cluster (idempotent)

---

ArgoCD picks up any Git changes and reconciles cluster state automatically — no deploy step is needed for app-only changes.
