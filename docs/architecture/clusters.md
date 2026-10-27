# Clusters

## Overview

Each Talos cluster is managed directly by Terraform, using the [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos/latest) provider — no self-hosted management plane (no Omni, no separate "core"/mgmt cluster on a third-party cloud). Each cluster self-hosts its own ArgoCD and is otherwise fully independent. ArgoCD handles application state exactly as it always has; Terraform now also handles Talos machine config generation, applying it to nodes, and cluster bootstrap.

## Cluster directory structure

Each cluster has a directory at `clusters/<cluster>/`:

| File | Purpose |
|------|---------|
| `apps.yaml` | Bootstrap ArgoCD app-of-apps — applied manually once to seed the cluster |

There is no `cluster.yaml` any more — Talos/Kubernetes versions, machine inventory, patches, and system extensions all live in Terraform now (see below), not in a per-cluster template file.

Raw Kubernetes manifests placed in `clusters/<cluster>/` are picked up directly by the app-of-apps as a second source and applied to the cluster. This is used for cluster-scoped resources that don't belong in any app chart (e.g. cluster-level RBAC, storage class config).

## Cluster naming

The fleet is currently two clusters, named for their role rather than a region code:

| Cluster | Short form (used in URLs/hostnames) | Role |
|---------|--------------------------------------|------|
| `production` | `prod` | Production workloads |
| `development` | `dev` | Lab/development workloads |

The full name (`production`/`development`) is used wherever Talos or Terraform has a literal cluster-identity field (the `siderolabs/talos` provider's `cluster_name`, the `cluster.name` Helm value passed to every app, etc). The short form (`prod`/`dev`) is used only in places that are explicitly shortened — currently just Headlamp's `console.<prod|dev>REDACTED` tailnet hostname (still within the standard `REDACTED` pattern — no admission-policy exception needed) and this module's own Infisical secret paths (`/k8s/talos/<prod|dev>/KUBECONFIG`). Existing internal `<name>.<cluster>REDACTED` hostnames across the rest of the app catalog use the full cluster name (e.g. `REDACTED`) — introducing a dedicated short-name parameter fleet-wide is a separate, later piece of work, not done as part of this change.

## Talos/Terraform module (`infra/terraform/modules/talos/`)

Per-cluster instantiation lives in `infra/terraform/talos-production.tf` / `talos-development.tf`, each a `module "talos_<cluster>"` block. The module:

1. **Generates machine secrets** (`talos_machine_secrets`) — CA material, bootstrap token, etc, held in Terraform state (Terraform Cloud). No external credential is needed beyond this; the provider talks to each node's `apid` directly using the generated client certificate.
2. **Builds an Image Factory schematic** (`talos_image_factory_schematic`) from the cluster's `system_extensions` list, and resolves installer/ISO URLs for it (`talos_image_factory_urls`) — this replaces Omni's "Download Installation Media" step. The resulting installer image reference is injected into every machine's config via `machine.install.image`.
3. **Generates machine configuration** (`talos_machine_configuration` data source, once per role — controlplane/worker) from: the shared patches in `infra/talos/patches/*.yaml` (templated, so `base.yaml`'s `${CLUSTER_NAME}` placeholder still resolves), the install-image/disk-selector patch from step 2, and any role-specific inline patches (e.g. control-plane-only scheduler config) declared directly in `talos-<cluster>.tf`.
4. **Layers each machine's own static-addressing patch on top, at apply time** (`talos_machine_configuration_apply`'s own `config_patches` argument), generated from `talos-<cluster>.tf`'s shared `network_interface` shape (bond/VLAN config, no addressing) plus that one machine's `ip` — every machine in a role shares the same base config from step 3 but needs a *different* address, which that step's single shared data source can't express.
5. **Applies it to every machine** (`talos_machine_configuration_apply`, one resource per node, keyed by the node's IP — see "The DHCP/static-IP chicken-and-egg problem" below for what it's actually keyed by on a machine's very first apply).
6. **Bootstraps etcd** on the first control plane node (`talos_machine_bootstrap`) — a one-time action, not re-run as config changes.
7. **Waits for cluster health** (`talos_cluster_health`), then **fetches a break-glass admin kubeconfig** (`talos_cluster_kubeconfig`) and stores it in Infisical at `/k8s/talos/<prod|dev>/KUBECONFIG`. Day-to-day human/CI access is unaffected — it still goes through the direct-OIDC path described in [Networking](networking.md); this is purely a disaster-recovery credential.

### The DHCP/static-IP chicken-and-egg problem

A freshly imaged machine boots into Talos maintenance mode with no machine config yet, so the only address it has is whatever its DHCP server assigns — the static address (`ip`) above is itself delivered *by* that first config apply, not available before it. So step 4/5's very first apply for a given machine has to target its current DHCP address, not its intended static one.

Each `control_plane_nodes`/`worker_nodes` entry therefore carries both:
- `ip` — the permanent static address. Used for everything else: the generated static-addressing patch itself, the cluster endpoint, health checks, the kubeconfig fetch, every later config update.
- `bootstrap_ip` (optional) — overrides the *target* of that one machine's `talos_machine_configuration_apply`/`talos_machine_bootstrap` calls while it's set.

One-time procedure per machine:

1. Image and boot it (see "Registering new machines" below).
2. Read its DHCP-assigned address off the console, router, or DHCP lease table by hand.
3. Set that machine's `bootstrap_ip` to that address in `talos-<cluster>.tf`, commit, and apply.
4. Confirm the machine now answers at its static `ip` (e.g. `talosctl -e <ip> -n <ip> version`).
5. Remove `bootstrap_ip` from that machine's entry in a follow-up commit.

This is the same kind of first-time, must-happen-from-the-LAN step `hsctl run -e local` exists for in the automatron-removal PR — a human runs it locally, from the same network as the target, rather than from CI. Expect the health-check/kubeconfig steps (which always target the static `ip`) to fail on that very first apply if the machine hasn't fully settled onto its static address yet — that's fine, just re-run `terraform apply` once it has.

### Known gaps versus the old Omni-managed setup

- **No control-plane load balancer/VIP.** The module uses the first control plane node's own IP as the cluster endpoint. `production` (3 CP nodes) loses its endpoint if that specific node goes down, even though etcd/the rest of the control plane would still be healthy. Omni's embedded discovery service sidestepped this; nothing in this module does yet. Worth revisiting with a kube-vip machine patch if it matters in practice.
- **No equivalent of Omni's `backupConfiguration` (etcd snapshot backups to Omni's own storage).** The Talos Terraform provider has no feature for this; it would need a separate mechanism (e.g. a scheduled `talosctl etcd snapshot` somewhere) if etcd backups beyond VolSync's PVC-level backups are needed.

## Shared Talos patches

`infra/talos/patches/` (renamed from `infra/omni/patches/`) contains Talos machine config patches applied to every machine in a cluster, selected per-cluster via each module instantiation's `patch_files` list. Common patches:

- Kubelet server certificate rotation
- OIDC/JWT authentication wiring for the apiserver
- Disabling kube-proxy/Flannel (this fleet uses Cilium instead)

See [Talos configuration docs](https://www.talos.dev/latest/reference/configuration/) for the patch schema.

## Registering new machines

A machine needs no separate "registration" step with any external control plane any more — Terraform owns its config directly. To onboard one:

1. **Build a schematic and get an ISO** via the Image Factory HTTP API (`POST https://factory.talos.dev/schematics` with the target system extensions in `customization.systemExtensions.officialExtensions`; download the ISO from `https://factory.talos.dev/image/<schematic-id>/<talos-version>/metal-<arch>.iso`) — or just read the `schematic_id`/`iso_url` output already computed by the relevant `module.talos_<cluster>` instance, since it's the same schematic the cluster's other machines already run.
2. **Write the ISO to media** — USB drive (`dd if=<iso> of=/dev/<device> conv=fdatasync`) or mounted as virtual media via the server's BMC (iDRAC/iLO/IPMI).
3. **Boot the machine from it** — Talos boots into maintenance mode; the console prints its DHCP-assigned IP.
4. **Decide the machine's permanent static IP, and add it to `talos-<cluster>.tf`** — append `{ name = "<cluster>-cp-N", ip = "<the permanent static IP>", bootstrap_ip = "<its current DHCP IP from step 3>" }` to the relevant `control_plane_nodes`/`worker_nodes` list. Commit and merge — CI's `talos` job applies that machine's config directly (no separate claim/allocate step the way Omni required), including the static-addressing patch that gives it `ip` going forward.
5. **Confirm the static address took, then drop `bootstrap_ip`** — once the machine answers at its static `ip`, remove `bootstrap_ip` from its entry in a follow-up commit. See "The DHCP/static-IP chicken-and-egg problem" above for why this two-step dance exists.

Full walkthrough: [Registering new machines](../operations/registering-machines.md).

## Bootstrap: adding a new cluster

1. **Add a new `module "talos_<cluster>"` block** to `infra/terraform/`, following `talos-production.tf`/`talos-development.tf` as a template (versions, system extensions, patches, machine inventory).
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
4. **Merge to `main`** — CI's `talos` job generates machine config, applies it, and bootstraps the new cluster. Then run the cluster bootstrap playbook — `hsctl run bootstrap-cluster --cluster <name> -e remote` (dispatches `deploy.yaml`'s `ansible` job) — which seeds critical credentials (ArgoCD deploy key, Infisical operator creds, etc.) that the cluster's own self-hosted ArgoCD depends on at startup.
5. **Apply `clusters/<cluster>/apps.yaml` manually, once** — this is what the bootstrap playbook above actually applies; ArgoCD then takes over and syncs the app catalog going forward, in sync-wave order.

## Upgrading Talos or Kubernetes

Update `talos_version`/`kubernetes_version` in the relevant `module "talos_<cluster>"` block and merge to `main`. The `talos` CI job re-applies machine configuration across the cluster's machines; `kubernetes_version` only takes effect for new nodes bootstrapping — upgrading a running cluster's Kubernetes version requires the dedicated `talos_cluster` resource's `upgrade-k8s` workflow (not currently wired into this module — add it if/when a live Kubernetes upgrade is needed, rather than relying on `kubernetes_version` drift to trigger one).

## Terraform

Cloud resources (Cloudflare DNS, Infisical project setup, Tailscale configuration, Talos cluster provisioning) live in `infra/terraform/`. State is in [Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) (`homescale` org, `homescale` workspace).

CI authenticates to Infisical via GitHub OIDC. On merge to `main`, CI runs `terraform apply` automatically (after `scan` and `build` pass). On PRs, CI runs `terraform plan` and posts the plan as a PR comment. A human can also run Terraform directly via `hsctl run terraform -e local` (Infisical universal auth instead of GitHub OIDC) — the only way to bootstrap a cluster for the first time, before CI/Tailscale can reach it.

To format Terraform files locally:

```bash
terraform -chdir=infra/terraform fmt
```

### Terraform modules

| Module | What it manages |
|--------|----------------|
| `modules/tailscale/` | Tailscale ACL, tags, and OAuth clients — reads `tailscale:` blocks from `app.yaml` files via `fileset` |
| `modules/cloudflare/` | DNS records and Cloudflare Zero Trust Tunnel config — reads `exposePublic:` from `app.yaml` |
| `modules/infisical/` | Infisical project structure and machine identities. VolSync's per-app secret scaffolding is separate — see `volsync.tf` in the Terraform root |
| `modules/talos/` | A single Talos/Kubernetes cluster — machine secrets, Image Factory schematic, machine config generation/apply, bootstrap, health check, break-glass kubeconfig. Instantiated once per cluster (`talos-production.tf`, `talos-development.tf`) |
