# Clusters

## Overview

Each Talos cluster is managed directly by Terraform, using the [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos/latest) provider — no self-hosted management plane (no Omni, no separate "core"/mgmt cluster on a third-party cloud). Each cluster self-hosts its own ArgoCD and is otherwise fully independent. ArgoCD handles application state exactly as it always has; Terraform now also handles Talos machine config generation, applying it to nodes, and cluster bootstrap.

## Cluster directory structure

Each cluster has a directory at `clusters/<cluster>/`:

| File | Purpose |
|------|---------|
| `apps.yaml` | Bootstrap ArgoCD app-of-apps — applied manually once to seed the cluster |
| `cluster.yaml` | That cluster's Talos data: version pins, system extensions, network interface shape, inline config patches, machine inventory, and the LAN subnet(s) its own Tailscale subnet router should advertise (`tailscale.advertise_routes`). Pure data read by Terraform (`yamldecode`) — not an ArgoCD source; `apps.yaml` excludes it via `directory.exclude`. Rename to `cluster.yaml.disabled` to pull a cluster out of Terraform entirely (`production` is disabled this way right now) |

Raw Kubernetes manifests placed in `clusters/<cluster>/` are picked up directly by the app-of-apps as a second source and applied to the cluster. This is used for cluster-scoped resources that don't belong in any app chart (e.g. cluster-level RBAC, storage class config).

## Cluster naming

The fleet is currently two clusters, named for their role rather than a region code:

| Cluster | Short form (used in URLs/hostnames) | Role |
|---------|--------------------------------------|------|
| `production` | `prod` | Production workloads |
| `development` | `dev` | Lab/development workloads |

The full name (`production`/`development`) is used wherever Talos or Terraform has a literal cluster-identity field (the `siderolabs/talos` provider's `cluster_name`, the `cluster.name` Helm value passed to every app, etc). The short form (`prod`/`dev`) is used only in places that are explicitly shortened — currently just Headlamp's `console.<prod|dev>REDACTED` tailnet hostname (still within the standard `REDACTED` pattern — no admission-policy exception needed) and this module's own Infisical secret paths (`/k8s/talos/<prod|dev>/KUBECONFIG`). Existing internal `<name>.<cluster>REDACTED` hostnames across the rest of the app catalog use the full cluster name (e.g. `REDACTED`) — introducing a dedicated short-name parameter fleet-wide is a separate, later piece of work, not done as part of this change.

## Talos/Terraform module (`infra/terraform/modules/talos/`)

`infra/terraform/talos.tf` discovers every cluster directly from `clusters/*/cluster.yaml` (`fileset` + `yamldecode`, keyed by directory name) and instantiates the module once per cluster via a single `module "talos" { for_each = ... }` block — addressed per cluster as `module.talos["production"]`/`module.talos["development"]`. There's no separate Terraform file per cluster to create or maintain; adding a cluster is just adding its `cluster.yaml`. The module:

1. **Generates machine secrets** (`talos_machine_secrets`) — CA material, bootstrap token, etc, held in Terraform state (Terraform Cloud). No external credential is needed beyond this; the provider talks to each node's `apid` directly using the generated client certificate.
2. **Builds an Image Factory schematic** (`talos_image_factory_schematic`) from the cluster's `system_extensions` list, and resolves installer/ISO URLs for it (`talos_image_factory_urls`) — this replaces Omni's "Download Installation Media" step. The resulting installer image reference is injected into every machine's config via `machine.install.image`.
3. **Generates machine configuration** (`talos_machine_configuration` data source, once per role — controlplane/worker) from: every patch in `infra/talos/patches/base/` (applies to all clusters) plus every patch in `infra/talos/patches/<cluster>/` (applies only to this cluster) — both templated, so e.g. `base/cluster-name-label.yaml`'s `${CLUSTER_NAME}` placeholder still resolves — the install-image/disk-selector patch from step 2, and any role-specific inline patches (e.g. control-plane-only scheduler config) declared directly in that cluster's `cluster.yaml` (`control_plane.patches`/`workers.patches`).
4. **Layers each machine's own static-addressing patch on top, at apply time** (`talos_machine_configuration_apply`'s own `config_patches` argument), generated from `cluster.yaml`'s shared `network_interface` shape (bond/VLAN config, no addressing) plus that one machine's `ip` — every machine in a role shares the same base config from step 3 but needs a *different* address, which that step's single shared data source can't express.
5. **Applies it to every machine** (`talos_machine_configuration_apply`, one resource per node, keyed by the node's IP — see "The DHCP/static-IP chicken-and-egg problem" below for what it's actually keyed by on a machine's very first apply).
6. **Bootstraps etcd** on the first control plane node (`talos_machine_bootstrap`) — a one-time action, not re-run as config changes.
7. **Waits for cluster health** (`talos_cluster_health`), then **fetches a break-glass admin kubeconfig** (`talos_cluster_kubeconfig`) and stores it in Infisical at `/k8s/talos/<prod|dev>/KUBECONFIG`. Day-to-day human/CI access is unaffected — it still goes through the direct-OIDC path described in [Networking](networking.md); this is purely a disaster-recovery credential.

### The DHCP/static-IP chicken-and-egg problem

A freshly imaged machine boots into Talos maintenance mode with no machine config yet, so the only address it has is whatever its DHCP server assigns — the static address (`ip`) above is itself delivered *by* that first config apply, not available before it. So step 4/5's very first apply for a given machine has to target its current DHCP address, not its intended static one.

Each `control_plane.nodes`/`workers.nodes` entry therefore carries both:
- `ip` — the permanent static address. Used for everything else: the generated static-addressing patch itself, the cluster endpoint, health checks, the kubeconfig fetch, every later config update.
- `bootstrap_ip` (optional) — overrides the *target* of that one machine's `talos_machine_configuration_apply`/`talos_machine_bootstrap` calls while it's set.

One-time procedure per machine:

1. Image and boot it (see "Registering new machines" below).
2. Read its DHCP-assigned address off the console, router, or DHCP lease table by hand.
3. Set that machine's `bootstrap_ip` to that address in `clusters/<cluster>/cluster.yaml`, commit, and apply.
4. Confirm the machine now answers at its static `ip` (e.g. `talosctl -e <ip> -n <ip> version`).
5. Remove `bootstrap_ip` from that machine's entry in a follow-up commit.

This is the same kind of first-time, must-happen-from-the-LAN step `hsctl run -e local` exists for in the automatron-removal PR — a human runs it locally, from the same network as the target, rather than from CI. Expect the health-check/kubeconfig steps (which always target the static `ip`) to fail on that very first apply if the machine hasn't fully settled onto its static address yet — that's fine, just re-run `terraform apply` once it has.

### Known gaps versus the old Omni-managed setup

- **No control-plane load balancer/VIP.** The module uses the first control plane node's own IP as the cluster endpoint. `production` (3 CP nodes) loses its endpoint if that specific node goes down, even though etcd/the rest of the control plane would still be healthy. Omni's embedded discovery service sidestepped this; nothing in this module does yet. Worth revisiting with a kube-vip machine patch if it matters in practice.
- **No equivalent of Omni's `backupConfiguration` (etcd snapshot backups to Omni's own storage).** The Talos Terraform provider has no feature for this; it would need a separate mechanism (e.g. a scheduled `talosctl etcd snapshot` somewhere) if etcd backups beyond VolSync's PVC-level backups are needed.

## Shared and cluster-specific Talos patches

`infra/talos/patches/` (renamed from `infra/omni/patches/`) contains Talos machine config patches, split into:

- `infra/talos/patches/base/` — applied to every machine in every cluster, automatically. Includes kubelet server certificate rotation, OIDC/JWT authentication wiring for the apiserver, disabling kube-proxy/Flannel (this fleet uses Cilium instead), making control-plane nodes schedulable, and the cluster-name node label.
- `infra/talos/patches/<cluster>/` — applied only to that one cluster's machines, also automatically (e.g. `infra/talos/patches/production/longhorn.yaml`). A cluster with none of its own still needs the directory to exist (tracked via `.gitkeep`), since the module globs it unconditionally.

Neither directory needs listing anywhere in `cluster.yaml` — the module globs both at plan time (`infra/terraform/modules/talos/machine_config.tf`). Each patch file is named for what it does. See [Talos configuration docs](https://www.talos.dev/latest/reference/configuration/) for the patch schema.

## Registering new machines

A machine needs no separate "registration" step with any external control plane any more — Terraform owns its config directly. To onboard one:

1. **Build a schematic and get an ISO** via the Image Factory HTTP API (`POST https://factory.talos.dev/schematics` with the target system extensions in `customization.systemExtensions.officialExtensions`; download the ISO from `https://factory.talos.dev/image/<schematic-id>/<talos-version>/metal-<arch>.iso`) — or just read the `schematic_id`/`iso_url` output already computed by the relevant `module.talos["<cluster>"]` instance, since it's the same schematic the cluster's other machines already run.
2. **Write the ISO to media** — USB drive (`dd if=<iso> of=/dev/<device> conv=fdatasync`) or mounted as virtual media via the server's BMC (iDRAC/iLO/IPMI).
3. **Boot the machine from it** — Talos boots into maintenance mode; the console prints its DHCP-assigned IP.
4. **Decide the machine's permanent static IP, and add it to `clusters/<cluster>/cluster.yaml`** — append `{ name: "<cluster>-cp-N", ip: "<the permanent static IP>", bootstrap_ip: "<its current DHCP IP from step 3>" }` to the relevant `control_plane.nodes`/`workers.nodes` list. Commit and merge — CI's `talos` job applies that machine's config directly (no separate claim/allocate step the way Omni required), including the static-addressing patch that gives it `ip` going forward.
5. **Confirm the static address took, then drop `bootstrap_ip`** — once the machine answers at its static `ip`, remove `bootstrap_ip` from its entry in a follow-up commit. See "The DHCP/static-IP chicken-and-egg problem" above for why this two-step dance exists.

Full walkthrough: [Registering new machines](../operations/registering-machines.md).

## Bootstrap: adding a new cluster

A brand-new cluster has no Tailscale reachability at all until it has already bootstrapped and synced once — its own Tailscale subnet router (see [Networking](networking.md)) is an ArgoCD-managed workload inside it, not something that pre-exists on the LAN. So, unlike adding a machine to an *existing* cluster, **the entire first pass below runs locally** (`hsctl ... -e local`, from a machine physically on that LAN), not through CI. If another cluster already advertises the same LAN (e.g. `development` bootstrapping before `production`, both on `10.1.245.0/24`), CI *may* already be able to reach the new nodes via that other cluster's router — but don't rely on it for a cluster's own first bootstrap; do it locally regardless.

1. **Create `clusters/<cluster>/cluster.yaml`** (versions, system extensions, network interface shape, machine inventory, `tailscale.advertise_routes` — follow `clusters/development/cluster.yaml` as a template) and, if it needs any of its own, an `infra/talos/patches/<cluster>/` directory (a `.gitkeep` if empty). `infra/terraform/talos.tf` discovers it automatically — no Terraform file to create.
2. **Create `clusters/<cluster>/apps.yaml`** — the ArgoCD app-of-apps pointing at this repo. Give its `clusters/<cluster>` directory source `directory: { recurse: true, exclude: cluster.yaml* }`, same as `production`/`development` — otherwise ArgoCD (and `validate-manifests.sh`) try to apply `cluster.yaml` as a Kubernetes manifest. Also set `apps.tailscale.values.subnetRouter.advertiseRoutes` to the same CIDR(s) as `cluster.yaml`'s `tailscale.advertise_routes` — the two are separate (one's Terraform-only data, the other's what Helm actually renders) but need to agree.
3. **Add any other deployment overrides**, if needed, to that same `clusters/<cluster>/apps.yaml`'s `apps` source values (see [Deployment overrides](../operations/deploying-an-app.md#deployment-overrides)).
4. **Image and boot the machine(s)** — see [Registering new machines](#registering-new-machines) below. Record each one's DHCP-assigned IP, decide its permanent static IP, and fill in `control_plane.nodes`/`workers.nodes` in `cluster.yaml` with both (`ip` + `bootstrap_ip`).
5. **From a machine on that LAN, run `hsctl run terraform -e local`** (untargeted — it covers the whole `infra/terraform` workspace, Talos module included). This generates the Image Factory schematic, applies machine config to each node (via `bootstrap_ip` the first time), bootstraps etcd, waits for cluster health, and stores a break-glass kubeconfig in Infisical at `/k8s/talos/<short>/KUBECONFIG`. Confirm each node now answers at its static `ip`, then drop `bootstrap_ip` and re-run the same command once more (still locally — the subnet router still doesn't exist yet) to reconcile that removal.
6. **Still from that LAN, run `hsctl run bootstrap-cluster --cluster <name> -e local`** — seeds the critical credentials (ArgoCD deploy key, Infisical operator creds) the cluster's own self-hosted ArgoCD needs at startup, and installs Cilium.
7. **Apply `clusters/<cluster>/apps.yaml` manually, once**, against the kubeconfig from step 5 (still only reachable from that LAN at this point). ArgoCD takes over from here, syncing in sync-wave order: Infisical → cert-manager/ArgoCD/RBAC → **Tailscale** (this is where the subnet router actually comes up and advertises the LAN) → external-dns → apps.
8. **Confirm the route is live and auto-approved** (`tailscale status` from an admin device, or the Tailscale admin console) — Terraform's `autoApprovers.routes` entry for this CIDR means no manual approval step should be needed. From here on, CI (`tag:github-actions`) and `sg-k8s-admin` members can reach this cluster's LAN directly, and any future `hsctl run ... -e remote` against it works normally.

## Upgrading Talos or Kubernetes

Update `talos_version`/`kubernetes_version` in the relevant `clusters/<cluster>/cluster.yaml` and merge to `main`. The `talos` CI job re-applies machine configuration across the cluster's machines (this works remotely once the cluster has its own subnet router up — see [Networking](networking.md)); `kubernetes_version` only takes effect for new nodes bootstrapping — upgrading a running cluster's Kubernetes version requires the dedicated `talos_cluster` resource's `upgrade-k8s` workflow (not currently wired into this module — add it if/when a live Kubernetes upgrade is needed, rather than relying on `kubernetes_version` drift to trigger one).

## Terraform

Cloud resources (Cloudflare DNS, Infisical project setup, Tailscale configuration, Talos cluster provisioning) live in `infra/terraform/`. State is in [Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) (`homescale` org, `homescale` workspace).

CI authenticates to Infisical via GitHub OIDC. On merge to `main`, CI runs `terraform apply` automatically (after `scan` and `build` pass). On PRs, CI runs `terraform plan` and posts the plan as a PR comment. A human can also run Terraform directly via `hsctl run terraform -e local` (Infisical universal auth instead of GitHub OIDC) — the only way to bootstrap a brand-new cluster, since CI has no Tailscale route to it until its own in-cluster subnet router is up (see [Networking](networking.md) and "Bootstrap: adding a new cluster" above).

To format Terraform files locally:

```bash
terraform -chdir=infra/terraform fmt
```

### Terraform modules

| Module | What it manages |
|--------|----------------|
| `modules/tailscale/` | Tailscale ACL, tags, and OAuth clients — reads `tailscale:` blocks from `app.yaml` files via `fileset`, and each cluster's `tailscale.advertise_routes` from `cluster.yaml` (for grants + `autoApprovers.routes`) |
| `modules/cloudflare/` | DNS records and Cloudflare Zero Trust Tunnel config — reads `exposePublic:` from `app.yaml` |
| `modules/infisical/` | Infisical project structure and machine identities. VolSync's per-app secret scaffolding is separate — see `volsync.tf` in the Terraform root |
| `modules/talos/` | A single Talos/Kubernetes cluster — machine secrets, Image Factory schematic, machine config generation/apply, bootstrap, health check, break-glass kubeconfig. Instantiated once per cluster via `talos.tf`'s `for_each` over `clusters/*/cluster.yaml` |
