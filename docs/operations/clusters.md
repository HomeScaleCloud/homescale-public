# Cluster Operations

## Cluster files

Each cluster lives in `clusters/<cluster>/`:

| File | Purpose |
|------|---------|
| `apps.yaml` | Bootstrap ArgoCD app-of-apps (applied manually once) |
| `cluster.yaml` | Omni cluster template (Talos/k8s versions, machine assignments, patches); uses `$CLUSTER_NAME` envsubst at deploy time |

Shared Talos machine config patches are in `infra/omni/patches/` and applied to clusters during Omni template sync.

## Adding a new cluster

1. Create `clusters/<cluster>/` with `apps.yaml` and `cluster.yaml`.
2. Add the cluster name to any per-cluster overrides in `apps/*/app.yaml` as needed.
3. Apply `apps.yaml` manually once to bootstrap ArgoCD on the new cluster.
4. ArgoCD takes over from there.

## Terraform

Cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, NetBird config, mgmt cluster bootstrap) live in `infra/terraform/`. State is in Terraform Cloud (`homescale` org, `homescale` workspace).

```bash
# Plan
terraform -chdir=infra/terraform plan

# Format
terraform -chdir=infra/terraform fmt
```
