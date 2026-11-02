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

# Render the top-level app catalog (requires env.name)
helm template apps -f apps/values.yaml --set env.name=production

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
- `values` — Helm values passed through; may use `{{ .Values.env.name }}` and `{{ .Values.env.region }}` templating

Deployment overrides no longer live in `app.yaml`. Instead, `clusters/<cluster>/apps/apps.yaml` (see below) carries an `apps:` map, keyed by app directory name, in its `apps` source's inline `helm.values` block:
- `apps.<app-name>.deploy: true|false` — per-cluster override of that app's `defaultDeploy`
- `apps.<app-name>.*` — any other field deep-merges over that app's base `app.yaml`, for this cluster only

```yaml
# clusters/production/apps/apps.yaml, spec.sources[1].helm.values
env:
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

- `clusters/<cluster>/apps/apps.yaml` — the bootstrap ArgoCD app-of-apps (applied manually once); its own directory source points at `clusters/<cluster>/apps` specifically, not the parent, so nothing else under `clusters/<cluster>/` (the Talm project, `tailscale.yaml`) is in ArgoCD's sync scope
- `clusters/<cluster>/tailscale.yaml` — Terraform-only data, not an ArgoCD source: the LAN subnet(s) that cluster's own Tailscale subnet router advertises (`advertise_routes` — see Networking below)
- everything else directly under `clusters/<cluster>/` (`Chart.yaml`, `values.yaml`, `templates/`, `charts/`, `values/`, `nodes/`) is that cluster's Talm project — see "Talos cluster provisioning" below

#### Talos cluster provisioning (Talm, no Terraform)

Talos itself is **not** Terraform-managed — no Talos secrets, kubeconfig, or machine config live in Terraform state. Each cluster's own `clusters/<cluster>/` directory doubles as its Talm project (`talm init -p generic -N <cluster> ...`, [`talm`](https://github.com/cozystack/talm)), driven by `hsctl run talm --cluster <cluster> -- <talm args>` (see "The `hsctl run talm` wrapper" below) — distinct from `clusters/<cluster>/apps/` (the ArgoCD app-of-apps, unrelated to Talm) and `clusters/<cluster>/tailscale.yaml`, which happen to live alongside it. `clusters/<cluster>/values.yaml` holds that cluster's network topology (bond/VLAN shape, cluster endpoint); `clusters/<cluster>/values/<node>.yaml` holds each node's own static address override, needed only because `values.yaml` is shared across every node Talm renders from the same role template. `clusters/<cluster>/nodes/<node>.yaml` are Talm's own rendered, committed node files (discovered hardware + machine config) — not secrets, safe to commit.

`infra/talm/patches/base/*.yaml` and `infra/talm/patches/<cluster>/*.yaml` are plain Talos config-patch YAML (unchanged in shape from the old Terraform-era patches) — not auto-applied by anything; they're stacked explicitly as `talm apply`/`talm template` side-patches (`-f nodes/<node>.yaml -f ../../infra/talm/patches/base/foo.yaml -f ../../infra/talm/patches/<cluster>/bar.yaml ...`, relative to the project dir `clusters/<cluster>/` since patches live outside it, under `infra/talm/`). A patch can gate itself on this cluster's node count via a top-level `apply_conditions.nodes.min: N` key (e.g. `patches/base/spegel-containerd.yaml` requires 3+ nodes) — this is documentation a human checks before deciding whether to include that patch in a given cluster's `-f` chain, not something auto-enforced; Talos would reject the `apply_conditions` key itself if it were left in, so don't stack it as-is without stripping that key first if you ever need to hand-edit one. A cluster-identifying label (`REDACTED/name`) is baked directly into the project's own `templates/_helpers.tpl` (as `{{ .Chart.Name }}`) rather than a per-cluster patch — patches are never run through Helm's template engine (they're applied via Talos's own `configpatcher`, on raw bytes), so only something that already differs per-cluster by being a separate project directory (the chart name) could use this trick; anything that needs real per-cluster *values* still has to be a real patch file, or a `values/<node>.yaml` override.

**Secrets.** `talm init` generates a cluster's `secrets.yaml` (Talos CA/tokens) and `talosconfig` once, locally, as plain files — these are git-ignored (never committed) and, per this repo's convention, never encrypted-and-committed either (Talm supports that via `talm.key`+age; we don't use it). Instead they live in Infisical at `/k8s/talos/<prod|dev>/` (`SECRETS_YAML`, `TALOSCONFIG`, `KUBECONFIG`) — the `hsctl run talm` wrapper fetches them into `clusters/<cluster>/` before every invocation and pushes back whatever's there afterward, so Infisical stays the one source of truth.

#### The `hsctl run talm` wrapper

```
hsctl run talm --cluster <production|development> -- <talm args...>
```

Everything after `--` is forwarded verbatim to the real `talm` binary, run from `clusters/<cluster>/`. The wrapper (`_run_talm` in `hsctl.d/run.sh`) fetches `secrets.yaml`/`talosconfig`/`kubeconfig` from Infisical into that directory first (silently skipping any that don't exist yet — normal on a cluster's very first bootstrap), exports `TALOSCONFIG` to point at the fetched file, runs `talm` with the forwarded args, then pushes back whichever of those three files exist afterward. Always local — talm dials Talos nodes directly over the LAN the same way `talosctl` does, so `-e remote`/`--chain`/`--dry-run` don't apply to it, and it never clones a fresh checkout the way `hsctl run terraform -e local`/`hsctl run bootstrap-cluster -e local` do.

#### Registering new machines

1. Build a schematic and get an ISO via the Image Factory HTTP API (`POST https://factory.talos.dev/schematics`, system extensions in `customization.systemExtensions.officialExtensions`; ISO at `https://factory.talos.dev/image/<schematic-id>/<talos-version>/metal-<arch>.iso`).
2. Write the ISO to a USB drive (`dd if=<iso> of=/dev/<device> conv=fdatasync`) or mount it as virtual media via the server's BMC (iDRAC/iLO/IPMI).
3. Boot the machine from it — Talos boots into maintenance mode and prints its DHCP-assigned IP.
4. From a machine on the same LAN, render that node's config for the first time: `hsctl run talm --cluster <cluster> -- --nodes <dhcp-ip> -e <dhcp-ip> template -t templates/controlplane.yaml --values values/<node>.yaml > nodes/<node>.yaml`, then `hsctl run talm --cluster <cluster> -- apply -f nodes/<node>.yaml -i` (`-i`/`--insecure` targets the unauthenticated maintenance-mode API). Stack whichever `../../infra/talm/patches/base/*.yaml`/`../../infra/talm/patches/<cluster>/*.yaml` apply (see "Talos cluster provisioning" above) as additional `-f` args on the `apply`, in the same command.
5. Commit the resulting `nodes/<node>.yaml` — it's Talm's own record of that machine's discovered hardware and rendered config, not a secret.

This all has to happen from the LAN — there's no subnet router advertising it yet (that's an ArgoCD-managed workload inside the cluster itself, which doesn't exist until the cluster has already bootstrapped and synced once). See "Bootstrap: adding a new cluster" in `docs/architecture/clusters.md` for the full sequence, including etcd bootstrap and the first ArgoCD sync.

### Infrastructure (`infra/`)

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, Tailscale ACL/tags, Talos cluster provisioning). State is in Terraform Cloud (`homescale` org, `homescale` workspace). `infra/terraform/plan-apply.sh` is the shared plan/apply logic CI's `terraform` job and `hsctl run terraform -e local` both call.
- `infra/ansible/` — Bootstrapping playbooks (e.g., workload cluster bootstrap), run by CI's `ansible` job or `hsctl run <playbook> -e local`
- `infra/talm/patches/` — Talos machine config patches, stacked explicitly as `talm apply`/`talm template` side-patches: `base/` for every cluster, `<cluster>/` for that one cluster only — see "Talos cluster provisioning" above. Each cluster's own Talm project (`talm init`'d: `Chart.yaml`, `values.yaml`, `templates/`, `nodes/`) lives at `clusters/<cluster>/`, not under `infra/` — see "Clusters" above and "Talos cluster provisioning" below

### Secrets

Infisical is the secrets store. The Infisical k8s operator (deployed as an ArgoCD app with syncWave -35) syncs secrets from Infisical into cluster namespaces. No secrets belong in this repo — the `detect-secrets` pre-commit hook will catch them. The `# pragma: allowlist secret` comment suppresses false positives on non-secret strings like secret names.

### CI/CD Pipelines

Three jobs in `deploy.yaml`, called (along with `scan`/`build`/`mirror`) from `ci.yaml`:
- **scan** — pre-commit, PR title lint (Conventional Commits), CodeQL, Trivy config scan
- **build** — builds only changed apps on PRs and on pushes to main (all apps on a published release), builds Docker images, runs Trivy image scan; Helm charts are linted but not published
- **deploy** (`terraform` → `ansible`) — runs `terraform`/`ansible-playbook` directly on the runner, serialized repo-wide via a `concurrency: deploy` group. There is no CI job for Talos provisioning — that's always `hsctl run talm`, run locally (see "The `hsctl run talm` wrapper" above).
  - **`terraform`** — plans on every PR/push (posts the plan as a PR comment, including the rendered Tailnet ACL as an artifact), applies on merge to `main` (gated by a GitHub Environment). Authenticates to Infisical via GitHub OIDC (`provider "infisical"`'s default `oidc` auth method, `infra/terraform/providers.tf`) — no Tailscale needed, everything it talks to (Cloudflare, Terraform Cloud, Infisical, Vultr) is a public API. Shared plan/apply logic lives in `infra/terraform/plan-apply.sh`.
  - **`ansible`** — only runs on `workflow_dispatch` (manual trigger, or `hsctl run <name> -e remote`'s default dispatch path — see `docs/operations/hsctl.md`); runs `bootstrap-core`/`bootstrap-cluster`/any other `infra/ansible/playbooks/*.yml`. Needs Tailscale (joins as an ephemeral node) — `bootstrap-cluster` fetches its target cluster's kubeconfig from Infisical (`/k8s/talos/<prod|dev>/KUBECONFIG`, pushed there by the `hsctl run talm` wrapper after a `talm kubeconfig`), then reaches that cluster's apiserver directly over its own subnet-routed LAN. Only works once that cluster already has its own subnet router up (see "Talos cluster provisioning" above) — a brand-new cluster's first `bootstrap-cluster` run has to happen locally instead (`-e local`).
  - `workflow_dispatch` also lets `terraform` run on demand outside its push/PR trigger (`inputs.job == 'terraform'`) — this is what `hsctl run terraform -e remote` dispatches to.

### Networking

Tailscale is the zero-trust mesh used for human and machine access to services — CI reaching internal infra, and service exposure to end users.
CI joins the tailnet as an ephemeral node (`tailscale/github-action`, tagged `tag:github-actions`, removed when the job completes) in the `ansible` job, to reach a cluster's apiserver for `bootstrap-cluster`. `terraform` (the general workspace) never joins — it only calls public APIs. `tag:github-actions` is also a valid `sources` identifier any app's own `tailscale:` policy block can grant access to (see below) — currently no app does.

**LAN reachability — per-cluster subnet routers.** There is no standalone/dedicated subnet-router device; each cluster runs its own, in-cluster, as part of the `tailscale` app — a `Connector` resource (`apps/tailscale/templates/connector-subnet-router.yaml`, rendered only when `.Values.subnetRouter.advertiseRoutes` is set) advertising the LAN its own nodes physically sit on, declared per cluster as `advertise_routes` in `clusters/<cluster>/tailscale.yaml` and mirrored into that cluster's `apps.yaml` override (`apps.tailscale.values.subnetRouter.advertiseRoutes` — the two can't share one source: `tailscale.yaml` is Terraform-only data, `apps.yaml` is what Helm/ArgoCD actually renders). Each cluster is on its own VLAN/subnet: `production` on `10.1.245.0/24`, `development` on `10.1.247.0/24`.

This is **not** available until a cluster has already bootstrapped and synced once (ArgoCD has to deploy the `tailscale` app before its `Connector` can advertise anything) — see "Bootstrap: adding a new cluster" in `docs/architecture/clusters.md` for what that means for a brand-new cluster's first apply. This is also why Talos provisioning itself (`hsctl run talm`) and a brand-new cluster's first `bootstrap-cluster` run are always local, never CI — nothing is reachable over Tailscale until after that first sync.

Terraform's `tailscale` module reads every `clusters/*/tailscale.yaml` (`advertise_routes`) to (a) auto-approve those routes (`autoApprovers.routes` in `acl.tf` — otherwise every advertised route needs manual approval in the Tailscale admin console) and (b) grant access to them: only `group:sg-k8s-admin@REDACTED` and `tag:github-actions` can reach a cluster's advertised LAN at all (`local.lan_grants` in `acl.tf`) — nothing else gets it, by design.

**Internal service exposure** — the `tailscale` app also deploys the official Tailscale Kubernetes Operator plus a shared per-cluster ingress `ProxyGroup` to every cluster. A Service opts in with `type: LoadBalancer` / `loadBalancerClass: tailscale`, annotated `tailscale.com/tags`/`tailscale.com/hostname`/`tailscale.com/proxy-group: ingress` (routes through the shared ProxyGroup instead of a dedicated proxy pod) and `external-dns.kubernetes.io/hostname` for a friendly `<name>.<cluster>REDACTED` CNAME, published by `external-dns` running in every cluster. The admission policy (`require-tailscale-service-annotations` in `apps/kyverno`) enforces that `REDACTED` suffix with no exception — Headlamp's two consoles (`REDACTED`/`REDACTED`) just use a friendlier short name (`console.<prod|dev>`) within that same pattern, rather than `headlamp.<cluster>`, so they pass the policy as-is.

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
- `local.k8s_grant` — workload-cluster apiserver proxies (`dst: tag:k8s-api`, the `tailscale` app's `kube-apiserver-proxy` Service) on `tcp:443`, for Infrastructure Platforms, Security Platforms, and `sg-k8s-admin`. `tag:app-headlamp` is deliberately **not** a source here any more — each Headlamp instance now talks only to its own in-cluster apiserver (default in-cluster serviceaccount, no Tailscale egress), not to every cluster's `kube-apiserver-proxy`, so it no longer needs this grant. (`local.omni_k8s_grant`, Omni's break-glass Kubernetes proxy grant, no longer exists — removed along with Omni/`core` itself. Talos cluster break-glass access now uses the admin kubeconfig stored in Infisical at `/k8s/talos/<prod|dev>/KUBECONFIG` — see "Secrets" under "Talos cluster provisioning" above — instead of a Tailscale-exposed proxy.)
- `local.lan_grants` — each cluster's advertised LAN subnet(s) (`local.cluster_advertise_routes`, read from every `clusters/*/tailscale.yaml`'s `advertise_routes`, deduped), for `sg-k8s-admin` and `tag:github-actions` only (`ip: ["*"]`) — see Networking above. Empty (no grant at all) until at least one cluster declares a route.

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

The restic credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, etc.) live in a secret named `<app>-volsync-repo` in the app's namespace, synced from Infisical at `/k8s/volsync/<cluster-name>/<app>` via an `InfisicalSecret` CR in the app's `templates/secret.yaml`. Since that repository path is derived from the deploying cluster's own `.Values.env.name`, restoring into a cluster under a different name than the one the backup was written under (e.g. after a rename, or standing up a replacement cluster) needs an explicit `volsync.restore.sourceEnv` override — otherwise it resolves to a fresh, empty path under the new name instead of the old backup data. `apps/home-assistant/templates/secret.yaml` implements this (`{{ (((($.Values).volsync).restore).sourceEnv) | default $.Values.env.name }}`); other apps' `secret.yaml` would need the same pattern added before they could use it. It's a one-time bootstrap workaround, not a standing feature — remove the `sourceEnv` override (along with `restore.enabled`) once the restore is confirmed, so ongoing backups resume writing under the cluster's real name.

### Restore procedure

1. **Find the snapshot you want** (optional):
   ```bash
   hsctl get snapshot <app>
   ```

2. **Scale down and enable restore** in `clusters/<cluster>/apps/apps.yaml`'s `apps` source values. For example, for home-assistant on `production`:
   ```yaml
   # clusters/production/apps/apps.yaml, spec.sources[1].helm.values
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

5. **Scale back up and disable restore** — remove both the scale down and `volsync.restore` override from `clusters/<cluster>/apps/apps.yaml` in one commit, push. ArgoCD syncs, deletes the `ReplicationDestination`, creates/recreates the `ReplicationSource`, and scales the deployment back up.
