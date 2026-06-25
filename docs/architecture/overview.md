# Architecture Overview

HomeScale runs multiple Kubernetes clusters managed via GitOps. ArgoCD on each cluster watches this repo; a bootstrap `apps.yaml` in `clusters/<cluster>/` is an ArgoCD app-of-apps with two sources:

1. `clusters/<cluster>/` — raw Kubernetes manifests for that cluster
2. `apps/` — the Helm chart that generates per-cluster ArgoCD Application objects

## Cluster topology

| Cluster | Role |
|---------|------|
| `mgmt` | Management cluster; runs ArgoCD, Infisical operator, shared infra |
| `boa1-prod` | Production workloads in region `boa1` |
| `boa1-gw` | Gateway cluster for region `boa1` (PXE boot, subnet routing) |

Gateway clusters (`*-gw`) serve three roles:

- **Bare-metal provisioning** — runs `omni-infra-provider` to PXE-boot Talos nodes in the region
- **Subnet routing** — NetBird subnet router exposing BMC/MGMT subnets across the mesh
- **Region ↔ mgmt connectivity** — bridges region-local services to the central `mgmt` cluster

## App catalog (`apps/`)

`apps/` is a Helm chart. `apps/templates/applications.yaml` loops over every `apps/*/app.yaml` and generates an ArgoCD `Application` for each app enabled for the current cluster.

### `app.yaml` fields

| Field | Description |
|-------|-------------|
| `defaultDeploy` | Whether to deploy to all clusters by default |
| `clusters.<name>.deploy` | Per-cluster override of `defaultDeploy` |
| `path` | Path to the actual Helm chart |
| `namespace` | Target namespace |
| `syncWave` | ArgoCD sync wave (bootstrap order below) |
| `values` | Helm values; may use `{{ .Values.cluster.name }}` templating |

### Sync wave order

| Wave | Apps |
|------|------|
| -35 | infisical |
| -30 | cert-manager, argocd, rbac |
| -20 | netbird |
| -10 | external-dns |
| 0 | all other apps |
