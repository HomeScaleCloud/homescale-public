# Cluster Operations

## Overview

Each cluster is managed by [Omni](https://omni.siderolabs.com/) (SaaS control plane) running [Talos Linux](https://www.talos.dev/) nodes. Omni handles the low-level cluster lifecycle — provisioning, upgrading, machine assignments — while ArgoCD handles application state.

## Cluster directory structure

Each cluster has a directory at `clusters/<cluster>/`:

| File | Purpose |
|------|---------|
| `apps.yaml` | Bootstrap ArgoCD app-of-apps — applied manually once to seed the cluster |
| `cluster.yaml` | Omni cluster template (Talos/k8s versions, machine selectors, patch overrides) |

Raw Kubernetes manifests placed in `clusters/<cluster>/` are picked up directly by the app-of-apps as a second source and applied to the cluster. This is used for cluster-scoped resources that don't belong in any app chart (e.g. cluster-level RBAC, storage class config).

## Cluster naming

Clusters follow the `<region>-<role>` convention:

| Pattern | Example | Role |
|---------|---------|------|
| `<region>-prod` | `boa1-prod` | Production workloads |
| `<region>-gw` | `boa1-gw` | Gateway: bare-metal provisioning, subnet routing |
| `mgmt` | `mgmt` | Management (exception to the naming convention) |

Each cluster maps to exactly one region. Region codes are short datacenter identifiers (e.g. `boa1`).

## Cluster template (`cluster.yaml`)

`cluster.yaml` is an [Omni cluster template](https://omni.siderolabs.com/reference/cluster-templates). It specifies:

- Talos Linux version
- Kubernetes version
- Machine selectors (which physical machines are assigned to this cluster and their roles — control plane vs worker)
- Talos config patches to apply on top of the shared defaults

The template uses `$CLUSTER_NAME` as an envsubst substitution that CI replaces at deploy time. Shared Talos config patches live in `infra/omni/patches/` and are applied to all clusters unless overridden.

## Shared Talos patches

`infra/omni/patches/` contains Talos machine config patches applied during Omni template sync. Common patches:

- KubeSpan configuration (node-to-node WireGuard tunnels)
- Custom kubelet flags
- NTP configuration
- Kernel module loading

See [Talos configuration docs](https://www.talos.dev/latest/reference/configuration/) for the patch schema.

## Bootstrap: adding a new cluster

!!! note
    This is a one-time manual process. After bootstrap ArgoCD manages everything.

1. **Create the cluster in Omni** — assign machines, set Talos/k8s versions
2. **Create `clusters/<cluster>/`** with:
   - `cluster.yaml` — Omni template for the new cluster
   - `apps.yaml` — ArgoCD app-of-apps pointing at this repo
3. **Add per-cluster overrides** to any `apps/*/app.yaml` that needs cluster-specific config:
   ```yaml
   clusters:
     my-new-cluster:
       deploy: true
       values:
         someKey: clusterSpecificValue
   ```
4. **Apply `apps.yaml` once** to bootstrap ArgoCD on the new cluster:
   ```bash
   kubectl apply -f clusters/<cluster>/apps.yaml
   ```
5. **ArgoCD takes over** — it syncs the app catalog and deploys all enabled apps in sync-wave order

For a gateway cluster, also ensure `omni-infra-provider` is enabled in the app catalog for that cluster (set `deploy: true` in its `app.yaml`).

## Upgrading Talos or Kubernetes

Update the version fields in `clusters/<cluster>/cluster.yaml` and merge to `main`. The `deploy` CI job runs Omni template sync, which triggers a rolling upgrade across the cluster's machines.

Omni handles the upgrade sequence — control plane nodes first, then workers — following [Talos upgrade best practices](https://www.talos.dev/latest/talos-guides/upgrading-talos/).

## Terraform

Cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, NetBird configuration, mgmt cluster bootstrap) live in `infra/terraform/`. State is in [Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) (`homescale` org, `homescale` workspace).

```bash
# Plan changes locally
terraform -chdir=infra/terraform plan

# Format
terraform -chdir=infra/terraform fmt
```

On merge to `main`, CI runs `terraform apply` automatically (after `scan` and `build` pass). On PRs, CI runs `terraform plan` and posts the plan as a PR comment.

### Terraform modules

| Module | What it manages |
|--------|----------------|
| `modules/netbird/` | NetBird policies, groups, and reverse proxy resources — reads `app.yaml` files via `fileset` |
| `modules/cloudflare/` | DNS records, Cloudflare tunnel ingress rules — reads `exposePublic:` from `app.yaml` |
| `modules/infisical/` | Infisical project structure and machine identity setup |
| `modules/digitalocean/` | DigitalOcean resources (mgmt cluster node, block storage) |
