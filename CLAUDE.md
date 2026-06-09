# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A GitOps monorepo for **HomeScale** — private Kubernetes clusters for personal/family use. ArgoCD watches this repo and reconciles all cluster state automatically on merge to `main`.

## Key Commands

```bash
# Lint YAML (excludes apps/**/templates/** per .yamllint.yaml)
yamllint -c .yamllint.yaml .

# Format Terraform
terraform -chdir=infra/terraform fmt

# Run all pre-commit checks
pre-commit run --all-files

# Helm template render (validate a specific app chart)
helm template apps/<app-name> apps/<app-name>/

# Render the top-level app catalog (requires cluster.name)
helm template apps -f apps/values.yaml --set cluster.name=mgmt
```

Pre-commit runs automatically on commit. CI runs pre-commit, yamllint, detect-secrets, terraform fmt, CodeQL, and Trivy on every PR.

## Commit Convention

Conventional Commits are enforced by gitlint and CI:
```
type(scope): description
```
Types: `feat fix chore refactor docs style test perf ci build revert`

## Architecture

### GitOps Flow

ArgoCD on each cluster watches this repo. Each cluster has a bootstrap `apps.yaml` in `clusters/<cluster>/` that is an ArgoCD **app-of-apps**. That app-of-apps has two sources:
1. `clusters/<cluster>/` — any raw Kubernetes manifests for that cluster
2. `apps/` — the Helm chart that generates per-cluster ArgoCD Application objects

### App Catalog (`apps/`)

`apps/` is a Helm chart. `apps/templates/applications.yaml` loops over every `apps/*/app.yaml` and generates an ArgoCD `Application` for each app that is enabled for the current cluster.

Each `apps/<name>/app.yaml` controls deployment with these fields:
- `defaultDeploy: true|false` — whether to deploy to all clusters by default
- `clusters.<cluster-name>.deploy: true|false` — per-cluster override of `defaultDeploy`
- `clusters.<cluster-name>.*` — any other field merges/overrides the base `app.yaml`
- `path` — path to the actual Helm chart (required)
- `namespace` — target namespace (required)
- `syncWave` — ArgoCD sync wave; bootstrap order is: infisical (-35) → cert-manager/argocd/rbac (-30) → netbird (-20) → external-dns (-10) → apps (0)
- `values` — Helm values passed through; may use `{{ .Values.cluster.name }}` templating

Apps that contain a `Chart.yaml` and `Dockerfile` under `apps/<name>/` are built and pushed to `ghcr.io/homescalecloud/<name>` by CI.

### Clusters (`clusters/`)

One directory per cluster: `mgmt`, `prod`, `lab`, `boa1-mgmtr`.

- `clusters/<cluster>/apps.yaml` — the bootstrap ArgoCD app-of-apps (applied manually once)
- `clusters/<cluster>/cluster.yaml` — Omni cluster template (Talos/k8s versions, machine assignments, patches); uses `$CLUSTER_NAME` envsubst substitution at deploy time
- `clusters/patches/` — shared Talos machine config patches referenced by cluster definitions

### Infrastructure (`infra/`)

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, NetBird config, mgmt cluster bootstrap). State is in Terraform Cloud (`homescale` org, `homescale` workspace).
- `infra/ansible/` — Bootstrapping playbooks (e.g., Omni bootstrap)

### Secrets

Infisical is the secrets store. The Infisical k8s operator (deployed as an ArgoCD app with syncWave -35) syncs secrets from Infisical into cluster namespaces. No secrets belong in this repo — the `detect-secrets` pre-commit hook will catch them. The `# pragma: allowlist secret` comment suppresses false positives on non-secret strings like secret names.

### CI/CD Pipelines

Three reusable workflows called from `ci.yaml`:
- **scan** — pre-commit, PR title lint (Conventional Commits), CodeQL, Trivy config scan
- **build** — detects changed apps on PRs (or builds all on push to main), builds Docker images, runs Trivy image scan; Helm charts are linted but not published
- **deploy** — Terraform plan (PR) / apply (main) then Omni cluster template sync for changed clusters; both jobs connect to internal infrastructure via ephemeral NetBird setup keys

### Networking

Node-to-node connectivity across regions is handled by Talos KubeSpan, which automatically establishes WireGuard tunnels between all cluster nodes.

NetBird is a separate zero-trust WireGuard mesh used for human and machine access to services — CI reaching internal infra, and service exposure to end users.
CI jobs connect to internal infrastructure (Omni, Terraform providers) by joining the NetBird mesh with an ephemeral one-off setup key generated at the start of each workflow run and revoked at the end.

**Internal service exposure** — the `netbird-crs` app deploys a `NetworkRouter` CRD per cluster. The NetBird operator automatically registers each `NetworkResource` into the cluster's DNS zone (`<cluster>REDACTED`), making any k8s Service reachable at `<service-name>.<namespace>.<cluster>REDACTED` across the mesh.

**External service exposure** — a two-step pattern managed entirely in Terraform:
1. A NetBird reverse proxy resource is created pointing at the internal `REDACTED` FQDN. This gives the service an address under `REDACTED` (the reverse proxy domain registered in `netbird.tf`).
2. A Cloudflare `REDACTED` wildcard CNAME (in `dns.tf`) resolves to the NetBird reverse proxy cluster. Optionally a second Cloudflare CNAME is added for a friendlier public URL.
