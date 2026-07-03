# Clusters

## Overview

Each Talos cluster is managed by [Omni](https://omni.siderolabs.com/), a self-hosted cluster lifecycle manager running on the `mgmt` cluster. Omni handles provisioning, upgrades, and machine assignments. ArgoCD handles application state.

## Cluster directory structure

Each cluster has a directory at `clusters/<cluster>/`:

| File | Purpose |
|------|---------|
| `apps.yaml` | Bootstrap ArgoCD app-of-apps — applied manually once to seed the cluster |
| `cluster.yaml` | Omni cluster template (Talos/k8s versions, machine selectors, patch overrides). **Not present for `mgmt`** — see below. |

Raw Kubernetes manifests placed in `clusters/<cluster>/` are picked up directly by the app-of-apps as a second source and applied to the cluster (`cluster.yaml` is excluded from this source). This is used for cluster-scoped resources that don't belong in any app chart (e.g. cluster-level RBAC, storage class config).

### The `mgmt` cluster

`mgmt` is a managed [Vultr Kubernetes Engine](https://www.vultr.com/kubernetes/) cluster provisioned by Terraform (`infra/terraform/modules/mgmt_cluster/`, a single `vultr_kubernetes` resource). It does **not** have a `cluster.yaml` — Talos and Omni are not involved. Omni itself runs *on* `mgmt`, managing all
 other clusters.

## Cluster naming

Clusters follow the `<region>-<role>` convention:

| Pattern | Example | Role |
|---------|---------|------|
| `<region>-prod` | `boa1-prod` | Production workloads |
| `<region>-gw` | `boa1-gw` | Gateway: subnet routing |
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

- Custom kubelet flags
- NTP configuration
- Kernel module loading

See [Talos configuration docs](https://www.talos.dev/latest/reference/configuration/) for the patch schema.

## Machine classes

`infra/omni/machineclasses/` contains [Omni MachineClass](https://omni.siderolabs.com/reference/omni-resources/machine-class) resources. Machine classes define selectors that automatically assign bare-metal machines to clusters based on their labels or hardware attributes.

CI syncs all machine class files on every push to `main` (`omnictl apply -f infra/omni/machineclasses/<name>.yaml`) and dry-runs them on PRs. Changes to machine class files trigger the Omni job in the same way as `cluster.yaml` changes.

## Bootstrap: adding a new cluster

Machines must be registered with Omni before they can be claimed here — see [Registering new machines with Omni](../operations/registering-machines.md) if the machine isn't in the Omni **Machines** list yet.

1. **Create `clusters/<cluster>/cluster.yaml`** — the Omni cluster template defining Talos/k8s versions and machinesets. Commit and merge this first; CI syncs it to Omni, which creates the cluster and provisions the assigned machines.

   A minimal single-node control plane with a manually appointed machine:

   ```yaml
   kind: Cluster
   name: $CLUSTER_NAME
   kubernetes:
     version: v1.36.2
   talos:
     version: v1.13.5
   features:
     useEmbeddedDiscoveryService: true
     backupConfiguration:
       interval: 1h
   patches:
     - file: patches/base.yaml
     - file: patches/allow-scheduling-on-control-plane.yaml
   ---
   kind: ControlPlane
   machines:
     - <machine-uuid>
   ```
2. **Create `clusters/<cluster>/apps.yaml`** — the ArgoCD app-of-apps pointing at this repo.

3. **Add deployment overrides**, if needed, to that same `clusters/<cluster>/apps.yaml`'s `apps` source values (see [Deployment overrides](../operations/deploying-an-app.md#deployment-overrides)):
   ```yaml
   # clusters/my-new-cluster/apps.yaml, spec.sources[1].helm.values
   apps:
     my-app:
       deploy: true
       values:
         someKey: clusterSpecificValue
   ```
4. **Merge to `main`** — CI runs the Omni template sync, then the Ansible `bootstrap-cluster.yml` playbook runs automatically. The bootstrap playbook applies `apps.yaml` to the new cluster and seeds critical credentials (Infisical machine identities, kubeconfig, etc.) that apps depend on at startup.

5. **ArgoCD takes over** — it syncs the app catalog and deploys all enabled apps in sync-wave order

## Upgrading Talos or Kubernetes

Update the version fields in `clusters/<cluster>/cluster.yaml` and merge to `main`. The `deploy` CI job runs Omni template sync, which triggers a rolling upgrade across the cluster's machines.

Omni handles the upgrade sequence — control plane nodes first, then workers — following [Talos upgrade best practices](https://www.talos.dev/latest/talos-guides/upgrading-talos/).

## Terraform

Cloud resources (Cloudflare DNS, Vultr, Infisical project setup, NetBird configuration, mgmt cluster provisioning) live in `infra/terraform/`. State is in [Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) (`homescale` org, `homescale` workspace).

Terraform runs only in CI — it uses GitHub OIDC for Infisical auth and cannot be run locally. On merge to `main`, CI runs `terraform apply` automatically (after `scan` and `build` pass). On PRs, CI runs `terraform plan` and posts the plan as a PR comment.

To format Terraform files locally:

```bash
terraform -chdir=infra/terraform fmt
```

### Terraform modules

| Module | What it manages |
|--------|----------------|
| `modules/netbird/` | NetBird policies and groups — reads `netbird:` blocks from `app.yaml` files via `fileset` |
| `modules/cloudflare/` | DNS records and Cloudflare Zero Trust Tunnel config — reads `exposePublic:` from `app.yaml` |
| `modules/infisical/` | Infisical project structure and machine identities. VolSync's per-app secret scaffolding is separate — see `volsync.tf` in the Terraform root |
| `modules/mgmt_cluster/` | The `mgmt` Vultr Kubernetes cluster and its Infisical kubeconfig secret. Does not bootstrap ArgoCD — the bootstrap `apps.yaml` is applied manually once, per cluster |
| `modules/region/` | Regional bare-metal/cloud resources (NetBird subnet routing, secrets) — defined but not yet instantiated (commented out in `main.tf`) |
