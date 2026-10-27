# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A GitOps monorepo for **HomeScale** — private Kubernetes clusters for personal/family use. ArgoCD watches this repo and reconciles all cluster state automatically on merge to `main`.

## Documentation

The `docs/` directory is published to GitHub Pages via MkDocs Material to https://REDACTED. **Update the docs whenever you make a change that affects user-facing behavior**, including:

- Adding, removing, or changing any field in `app.yaml` (reference lives in `docs/architecture/apps.md`)
- Adding a new app or cluster
- Changing networking, secrets, or backup behavior
- Adding new `hsctl` commands or subcommands

### Alert runbooks

Every `PrometheusRule` alert must have a corresponding runbook in `docs/runbooks/<alert-name-kebab-case>.md` and an entry in the `mkdocs.yml` nav under the appropriate group. The alert must include a `runbook_url` annotation pointing to `https://REDACTED/runbooks/<alert-name-kebab-case>/`.

- **New alert** → create the runbook page, add it to `mkdocs.yml`, add `runbook_url` to the alert annotation.
- **Changed alert** (severity, thresholds, description, rename) → update the runbook to match.
- **Deleted alert** → remove the runbook page and `mkdocs.yml` entry.

This is enforced by `.github/scripts/check-runbooks.sh` (a `runbook-coverage` pre-commit hook, also run in CI): every repo-defined alert needs a `runbook_url` of the form above with a matching `docs/runbooks/<slug>.md` and `mkdocs.yml` nav entry, and every `docs/runbooks/*.md` must be claimed by an alert. The `<slug>` is taken from the `runbook_url` itself, so it doesn't have to be a mechanical kebab-case of the alert name.

Runbooks live under `docs/runbooks/` grouped by system (e.g. Longhorn alerts → `longhorn-*.md`, PDU alerts → `apc-pdu-*.md`). See existing runbooks for the expected format: header with severity/alert/dashboard, "What this means" section, "Common causes" table, remediation steps. No "Diagnosis" section — the alert firing is the diagnosis.

## Key Commands

```bash
# Lint YAML (excludes apps/**/templates/** per .yamllint.yaml)
yamllint -c .yamllint.yaml .

# Format Terraform
terraform -chdir=infra/terraform fmt

# Run all pre-commit checks
pre-commit run --all-files

# Helm template render (validate a specific app chart)
helm template <app-name> apps/<app-name>/

# Render the top-level app catalog (requires cluster.name)
helm template apps -f apps/values.yaml --set cluster.name=production

# Render every catalog + per-app chart the way ArgoCD would, for every cluster,
# then kubeconform the output against Kubernetes + datreeio CRD schemas. A CR
# whose kind has no schema fails the run unless allowlisted in the script.
# Needs helm, yq, kubeconform 0.7.x. Runs in CI on PRs.
.github/scripts/validate-manifests.sh
```

Pre-commit runs automatically on commit (includes yamllint and detect-secrets among its hooks). CI runs pre-commit, a Trivy config scan, and a Helm render + kubeconform pass (`validate-manifests.sh`) on every PR.

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
- `path` — path to the actual Helm chart (required)
- `namespace` — target namespace (required)
- `syncWave` — ArgoCD sync wave; bootstrap order is: infisical (-35) → cert-manager/argocd/rbac (-30) → tailscale (-20) → external-dns (-10) → apps (0)
- `values` — Helm values passed through; may use `{{ .Values.cluster.name }}` and `{{ .Values.cluster.region }}` templating

Deployment overrides no longer live in `app.yaml`. Instead, `clusters/<cluster>/apps.yaml` (see below) carries an `apps:` map, keyed by app directory name, in its `apps` source's inline `helm.values` block:
- `apps.<app-name>.deploy: true|false` — per-cluster override of that app's `defaultDeploy`
- `apps.<app-name>.*` — any other field deep-merges over that app's base `app.yaml`, for this cluster only

```yaml
# clusters/production/apps.yaml, spec.sources[1].helm.values
cluster:
  name: production
  region: boa1
apps:
  homepage:
    deploy: true
  longhorn:
    deploy: true
    values:
      replicaCount: 3
```

Apps that contain a `Chart.yaml` and `Dockerfile` under `apps/<name>/` are built and pushed to `ghcr.io/homescalecloud/<name>` by CI.

### Clusters (`clusters/`)

One directory per cluster. The fleet is currently two clusters, named for their role rather than a region code: `production` (formerly `boa1-prod`) and `development` (formerly `boa1-lab`). There is no `core`/management cluster any more — each cluster self-hosts its own ArgoCD and is fully independent; no third-party-cloud-hosted central cluster exists or is needed.

- `clusters/<cluster>/apps.yaml` — the bootstrap ArgoCD app-of-apps (applied manually once)

There is no `clusters/<cluster>/cluster.yaml` any more. Talos/Kubernetes versions, machine inventory (IPs), patches, and system extensions are all Terraform-managed instead — see "Talos cluster provisioning" below.

#### Talos cluster provisioning (Terraform, no Omni)

Each cluster is provisioned directly by Terraform's [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos/latest) provider — no self-hosted management plane. `infra/terraform/modules/talos/` is the module; `infra/terraform/talos-production.tf`/`talos-development.tf` each instantiate it once (`module "talos_production"`/`module "talos_development"`), carrying that cluster's Talos/Kubernetes version pins, system extensions, shared/inline config patches, and machine inventory (control-plane/worker node names + IPs).

Use the **full** cluster name (`production`/`development`) wherever Talos or this provider has a literal cluster-identity field (`talos_machine_configuration`'s `cluster_name`, etc) — this is also what every app's `.Values.cluster.name` Helm value is set to in `clusters/<cluster>/apps.yaml`, so existing internal `<name>.<cluster>REDACTED` hostnames fleet-wide now read e.g. `REDACTED`. Use the **short** form (`prod`/`dev`) only where something is explicitly shortened: currently just Headlamp's `console.<prod|dev>REDACTED` hostname (`.Values.cluster.shortName`, set alongside `.Values.cluster.name` in each `clusters/<cluster>/apps.yaml` — still within the standard `REDACTED` pattern, no admission-policy exception needed) and this module's own Infisical paths (`/k8s/talos/<prod|dev>/KUBECONFIG`). A fleet-wide short-name parameter for every app's own URLs is a separate, later piece of work, not done here.

The module, per cluster:
1. Generates machine secrets (`talos_machine_secrets`) — held only in Terraform state; the provider needs no separate credential beyond this, it talks to each node's `apid` directly via the generated client cert.
2. Builds an Image Factory schematic from `system_extensions` (`talos_image_factory_schematic`) and resolves installer/ISO URLs for it (`talos_image_factory_urls`) — this is the Terraform-era replacement for Omni's "Download Installation Media" wizard.
3. Generates machine config per role (`talos_machine_configuration` data source) from: the shared patches in `infra/talos/patches/*.yaml` (`templatefile`'d, so `base.yaml`'s `${CLUSTER_NAME}` placeholder — previously substituted by CI's envsubst before an `omnictl` sync — still resolves, now against this module's own `var.cluster_name`), an install-image/disk-selector patch built from step 2, and any role-specific inline patches (e.g. scheduler config) passed in from `talos-<cluster>.tf`.
4. Layers each machine's own static-addressing patch on top of that shared config, at apply time, via `talos_machine_configuration_apply`'s own `config_patches` argument — generated from `talos-<cluster>.tf`'s shared `network_interface` shape (bond/VLAN config, no addressing) plus that one machine's `ip`, since every machine in a role needs the *same* generated base config but a *different* address, which the role-wide `talos_machine_configuration` data source can't express on its own.
5. Applies it to every machine by IP (`talos_machine_configuration_apply`), bootstraps etcd on the first control-plane node once (`talos_machine_bootstrap`), waits for cluster health (`talos_cluster_health`), then fetches a break-glass admin kubeconfig and stores it in Infisical at `/k8s/talos/<prod|dev>/KUBECONFIG` (day-to-day access is unaffected — still the direct-OIDC path via the Tailscale apiserver-proxy described below).

**The DHCP/static-IP chicken-and-egg problem.** A freshly imaged machine boots into Talos maintenance mode with no machine config yet, so it only has a DHCP-assigned address — the static address `ip` above is itself delivered *by* the first config apply, not available before it. So step 4's very first apply for a given machine has to target that machine's current DHCP address, not its intended static one. `control_plane_nodes`/`worker_nodes` entries therefore carry both `ip` (the permanent static address — used for literally everything else: the generated static-addressing patch itself, the cluster endpoint, health checks, kubeconfig fetch, every later config update) and an optional `bootstrap_ip`, used only to override the *target* of that one machine's `talos_machine_configuration_apply`/`talos_machine_bootstrap` calls while it's set. The procedure, one time per machine: image and boot it (see "Registering new machines" below), read its DHCP address off the console/router/DHCP lease table by hand, set `bootstrap_ip` to that value in `talos-<cluster>.tf`, run `terraform apply`, confirm the machine now answers at its static `ip` (e.g. `talosctl -e <ip> -n <ip> version`), then remove `bootstrap_ip` again. This is exactly the kind of first-time, must-happen-from-the-LAN step `hsctl run -e local` exists for in the automatron-removal PR — a human runs it locally, from the same network as the target, rather than from CI. Expect the health-check/kubeconfig steps to fail on that first apply (they always target the static `ip`, which may not have taken effect yet mid-run) — that's fine, just re-run `terraform apply` once the machine has settled.

**Known gaps versus Omni**, not currently replicated: there's no control-plane load balancer/VIP (the module uses the first control-plane node's own IP as the cluster endpoint — fine for `development`'s single node, a real but accepted weak point for `production`'s 3), and there's no equivalent of Omni's `backupConfiguration` (etcd snapshot backups) — the Talos provider has no feature for this.

#### Registering new machines

No separate "registration"/claim step with an external control plane any more — Terraform owns machine config directly once an IP is in the relevant `talos-<cluster>.tf`:

1. Build a schematic and get an ISO via the Image Factory HTTP API (`POST https://factory.talos.dev/schematics`, system extensions in `customization.systemExtensions.officialExtensions`; ISO at `https://factory.talos.dev/image/<schematic-id>/<talos-version>/metal-<arch>.iso`) — or just read the relevant `module.talos_<cluster>`'s own `schematic_id`/`iso_url` Terraform outputs, since it's the same schematic that cluster's other machines already run.
2. Write the ISO to a USB drive (`dd if=<iso> of=/dev/<device> conv=fdatasync`) or mount it as virtual media via the server's BMC (iDRAC/iLO/IPMI).
3. Boot the machine from it — Talos boots into maintenance mode and prints its DHCP-assigned IP.
4. Decide the machine's permanent static IP, and add `{ name = "<cluster>-cp-N", ip = "<the static IP>", bootstrap_ip = "<its current DHCP IP from step 3>" }` to the relevant `control_plane_nodes`/`worker_nodes` list in `talos-<cluster>.tf`. Merge, apply (this is the "DHCP/static-IP chicken-and-egg problem" case above), confirm the machine now answers at its static IP, then remove `bootstrap_ip` in a follow-up commit.

The machine (and every other node in the cluster) must be reachable from wherever Terraform runs — directly, or via a Tailscale subnet router advertising the nodes' own LAN; CI's `talos` job joins the tailnet specifically for this.

Full walkthrough: `docs/operations/registering-machines.md`.

### Infrastructure (`infra/`)

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, Tailscale ACL/tags, Talos cluster provisioning). State is in Terraform Cloud (`homescale` org, `homescale` workspace). `infra/terraform/plan-apply.sh` is the shared plan/apply logic CI's `terraform` job and `hsctl run terraform -e local` both call.
- `infra/ansible/` — Bootstrapping playbooks (e.g., workload cluster bootstrap), run by CI's `ansible` job or `hsctl run <playbook> -e local`
- `infra/talos/patches/` — shared Talos machine config patches, applied directly by Terraform (`infra/terraform/modules/talos/`) to every machine in a cluster

### Secrets

Infisical is the secrets store. The Infisical k8s operator (deployed as an ArgoCD app with syncWave -35) syncs secrets from Infisical into cluster namespaces. No secrets belong in this repo — the `detect-secrets` pre-commit hook will catch them. The `# pragma: allowlist secret` comment suppresses false positives on non-secret strings like secret names.

### CI/CD Pipelines

Four jobs in `deploy.yaml`, called (along with `scan`/`build`/`mirror`) from `ci.yaml`:
- **scan** — pre-commit, PR title lint (Conventional Commits), CodeQL, Trivy config scan
- **build** — builds only changed apps on PRs and on pushes to main (all apps on a published release), builds Docker images, runs Trivy image scan; Helm charts are linted but not published
- **deploy** (`terraform` → `talos` → `ansible`) — runs `terraform`/`ansible-playbook` directly on the runner, serialized repo-wide via a `concurrency: deploy` group:
  - **`terraform`** — plans on every PR/push (posts the plan as a PR comment, including the rendered Tailnet ACL as an artifact), applies on merge to `main` (gated by a GitHub Environment). Authenticates to Infisical via GitHub OIDC (`provider "infisical"`'s default `oidc` auth method, `infra/terraform/providers.tf`) — no Tailscale needed, everything it talks to (Cloudflare, Terraform Cloud, Infisical, Vultr) is a public API. Shared plan/apply logic lives in `infra/terraform/plan-apply.sh`.
  - **`talos`** — detects changed `infra/terraform/talos-*.tf`/`infra/talos/patches/*.yaml` files, plans on PR (posts per-cluster PR comments) and applies on merge to `main`, `terraform -target=module.talos_<cluster>` for each affected cluster — this replaces the old Omni-sync job (there's no management cluster to dispatch to any more). Needs Tailscale to reach the Talos nodes' own IPs directly (see Networking below).
  - **`ansible`** — only runs on `workflow_dispatch` (manual trigger, or `hsctl run <name> -e remote`'s default dispatch path — see `docs/operations/hsctl.md`); runs `bootstrap-core`/`bootstrap-cluster`/any other `infra/ansible/playbooks/*.yml`. Also needs Tailscale — `bootstrap-cluster` fetches its target cluster's kubeconfig from Infisical (`/k8s/talos/<prod|dev>/KUBECONFIG`, written by the `talos` Terraform module), then reaches that cluster's apiserver directly over the same subnet-routed LAN the `talos` job uses.
  - `workflow_dispatch` also lets `terraform`/`talos` run on demand outside their push/PR triggers (`inputs.job == 'terraform'`/`'talos'`) — this is what `hsctl run terraform|talos -e remote` dispatches to.

### Networking

Tailscale is the zero-trust mesh used for human and machine access to services — CI reaching internal infra (the Talos nodes themselves, and the clusters they become), and service exposure to end users.
CI joins the tailnet as an ephemeral node (`tailscale/github-action`, tagged `tag:github-actions`, removed when the job completes) in the `talos`/`ansible` jobs — `talos` to reach the Talos nodes' own IPs directly for Terraform's machine-config apply/bootstrap, `ansible` to reach a cluster's apiserver for `bootstrap-cluster`. Both rely on a Tailscale subnet router advertising the nodes' own LAN. `terraform` (the general workspace) never joins — it only calls public APIs. `tag:github-actions` is also a valid `sources` identifier any app's own `tailscale:` policy block can grant access to (see below) — currently no app does.

**Internal service exposure** — the `tailscale` app deploys the official Tailscale Kubernetes Operator plus a shared per-cluster ingress `ProxyGroup` to every cluster. A Service opts in with `type: LoadBalancer` / `loadBalancerClass: tailscale`, annotated `tailscale.com/tags`/`tailscale.com/hostname`/`tailscale.com/proxy-group: ingress` (routes through the shared ProxyGroup instead of a dedicated proxy pod) and `external-dns.kubernetes.io/hostname` for a friendly `<name>.<cluster>REDACTED` CNAME, published by `external-dns` running in every cluster. The admission policy (`require-tailscale-service-annotations` in `apps/kyverno`) enforces that `REDACTED` suffix with no exception — Headlamp's two consoles (`REDACTED`/`REDACTED`) just use a friendlier short name (`console.<prod|dev>`) within that same pattern, rather than `headlamp.<cluster>`, so they pass the policy as-is.

**External service exposure** — public internet exposure goes through Cloudflare Zero Trust Tunnels via the `exposePublic:` app.yaml block, entirely independent of Tailscale.

### Tailscale access policies for apps

Each `apps/<name>/app.yaml` may include a top-level `tailscale:` block (outside of `values:`). This is **not a Helm value** — it is read directly by Terraform (`infra/terraform/modules/tailscale/acl.tf`) via `fileset` + `yamldecode` and flattened, along with every other app's rules, into a single `tailscale_acl` resource (Tailscale's ACL model is one policy document, not many discrete objects).

```yaml
tailscale:
  policy:
    rules:
      - sources: ["group:team-infra-plat@REDACTED", "app:myapp"]
        protocol: tcp
        ports: ["443", "9090"]
```

- `destinations` is always the app's own tag (`tag:app-<app-name>`), auto-registered in `tagOwners` by Terraform for every app directory.
- `sources` are literal ACL identifiers spelled out in full — no short-alias remapping: `group:<name>@REDACTED` for an Entra ID group (SCIM-synced into Tailscale), `tag:github-actions`, `tag:app-<name>` for another app's tag, or `*` for everyone.
- If an app has no `tailscale:` block, no access is granted for it (access is denied by default).

**Do not remove or treat this block as dead config** — it has no effect on Helm rendering but drives real infrastructure via Terraform.

In addition to the per-app rules above, the ACL always includes these grants defined directly in `acl.tf`, not app-specific policy:
- `local.self_grant` — every member reaches their own other devices on every port/protocol (`src: autogroup:member`, `dst: autogroup:self`, `ip: ["*"]`); Tailscale's standard self-access pattern.
- `local.remote_control_grant` — Infrastructure Platforms (`group:team-infra-plat@REDACTED`) reaches every tailnet endpoint (`dst: ["*"]`) on `tcp:5252`, the Tailscale client remote control web UI, and carries a `tailscale.com/cap/webui` app capability with `canEdit: ["*"]` granting full management/admin access (SSH, subnet routes, exit nodes, account settings) through that web UI on tagged devices.
- `local.k8s_grant` — workload-cluster apiserver proxies (`dst: tag:k8s-api`, the `tailscale` app's `kube-apiserver-proxy` Service) on `tcp:443`, for Infrastructure Platforms, Security Platforms, and `sg-k8s-admin`. `tag:app-headlamp` is deliberately **not** a source here any more — each Headlamp instance now talks only to its own in-cluster apiserver (default in-cluster serviceaccount, no Tailscale egress), not to every cluster's `kube-apiserver-proxy`, so it no longer needs this grant. (`local.omni_k8s_grant`, Omni's break-glass Kubernetes proxy grant, no longer exists — removed along with Omni/`core` itself. Talos cluster break-glass access now uses the admin kubeconfig the `talos` Terraform module stores in Infisical at `/k8s/talos/<prod|dev>/KUBECONFIG` instead of a Tailscale-exposed proxy.)

## VolSync Backups

VolSync (`apps/volsync/`, syncWave -5) provides PVC-level backup and restore via restic repositories.

### How backups work

Each app that needs backups has a `volsync.yaml` template with two halves gated by a Helm value. Under normal operation the `ReplicationSource` is active and runs on a schedule. When restore mode is enabled the `ReplicationSource` is suppressed and replaced by a one-shot `ReplicationDestination`.

To override the backup interval for a specific app, set `volsync.backupSchedule` in `app.yaml`:
```yaml
values:
  volsync:
    backupSchedule: "0 */2 * * *"  # every 2 hours
```

The restic credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, etc.) live in a secret named `<app>-volsync-repo` in the app's namespace, synced from Infisical at `/k8s/volsync/<cluster-name>/<app>` via an `InfisicalSecret` CR in the app's `templates/secret.yaml`. Since that repository path is derived from the deploying cluster's own `.Values.cluster.name`, restoring into a cluster under a different name than the one the backup was written under (e.g. after a rename, or standing up a replacement cluster) needs an explicit `volsync.restore.sourceCluster` override — otherwise it resolves to a fresh, empty path under the new name instead of the old backup data. `apps/home-assistant/templates/secret.yaml` implements this (`{{ (((($.Values).volsync).restore).sourceCluster) | default $.Values.cluster.name }}`); other apps' `secret.yaml` would need the same pattern added before they could use it. It's a one-time bootstrap workaround, not a standing feature — remove the `sourceCluster` override (along with `restore.enabled`) once the restore is confirmed, so ongoing backups resume writing under the cluster's real name.

### Restore procedure

1. **Find the snapshot you want** (optional):
   ```bash
   hsctl get snapshot <app>
   ```

2. **Scale down and enable restore** in `clusters/<cluster>/apps.yaml`'s `apps` source values. For example, for home-assistant on `production`:
   ```yaml
   # clusters/production/apps.yaml, spec.sources[1].helm.values
   apps:
     home-assistant:
       values:
         replicaCount: 0
         volsync:
           restore:
             enabled: true
             # optional — omit to restore the latest snapshot
             restoreAsOf: "2024-01-15T00:00:00Z"  # latest snapshot at or before this RFC3339 time
             previous: 3                            # or: Nth-most-recent (1=latest, 2=second-latest, …)
   ```

4. **Wait for the restore to complete**:
   ```bash
   kubectl -n <namespace> get replicationdestination <app>-restore -w
   ```
   Done when `.status.lastSyncTime` is set and conditions show `Reconciled=True`.

5. **Scale back up and disable restore** — remove both the scale down and `volsync.restore` override from `clusters/<cluster>/apps.yaml` in one commit, push. ArgoCD syncs, deletes the `ReplicationDestination`, creates/recreates the `ReplicationSource`, and scales the deployment back up.
