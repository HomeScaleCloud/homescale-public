# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A GitOps monorepo for **HomeScale** — private Kubernetes clusters for personal/family use. ArgoCD watches this repo and reconciles all cluster state automatically on merge to `main`.

## Documentation

The `docs/` directory is published to GitHub Pages via MkDocs Material. **Update the docs whenever you make a change that affects user-facing behavior**, including:

- Adding, removing, or changing any field in `app.yaml` (reference lives in `docs/operations/apps.md`)
- Adding a new app or cluster
- Changing networking, secrets, or backup behavior
- Adding new `hsctl` commands or subcommands

Build and preview locally:
```bash
# One-time setup
python3 -m venv .venv && source .venv/bin/activate && pip install mkdocs-material

# Serve with live reload
mkdocs serve
```

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
- `values` — Helm values passed through; may use `{{ .Values.cluster.name }}` and `{{ .Values.cluster.region }}` templating

Apps that contain a `Chart.yaml` and `Dockerfile` under `apps/<name>/` are built and pushed to `ghcr.io/homescalecloud/<name>` by CI.

### Clusters (`clusters/`)

One directory per cluster: `mgmt`, `boa1-prod`, `boa1-gw`. Cluster names follow the `<region>-<name>` convention (e.g. `boa1-prod`, `boa1-gw`); `mgmt` is the exception. Each cluster maps to exactly one region.

- `clusters/<cluster>/apps.yaml` — the bootstrap ArgoCD app-of-apps (applied manually once)
- `clusters/<cluster>/cluster.yaml` — Omni cluster template (Talos/k8s versions, machine assignments, patches); uses `$CLUSTER_NAME` envsubst substitution at deploy time

### Infrastructure (`infra/`)

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, NetBird config, mgmt cluster bootstrap). State is in Terraform Cloud (`homescale` org, `homescale` workspace).
- `infra/ansible/` — Bootstrapping playbooks (e.g., Omni bootstrap)
- `infra/omni/patches/` — shared Talos machine config patches applied to clusters during Omni template sync

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

**Gateway clusters (`*-gw`)** are single-node clusters, one per region. They serve as the regional entry point into the HomeScale mesh and handle three roles:
- **Bare-metal provisioning** — runs the Omni infra provider (`omni-infra-provider` app) to PXE-boot Talos nodes in the region
- **Subnet routing** — runs a NetBird subnet router that exposes the region's BMC and MGMT subnets across the WireGuard mesh
- **Region ↔ mgmt connectivity** — bridges region-local services to the central `mgmt` cluster and vice versa

The naming convention is `<region>-gw` (e.g. `boa1-gw`).

### NetBird access policies for apps

Each `apps/<name>/app.yaml` may include a top-level `netbird:` block (outside of `values:`). This is **not a Helm value** — it is read directly by Terraform (`infra/terraform/modules/netbird/policies.tf`) via `fileset` + `yamldecode` and used to create `netbird_policy` resources in the NetBird management plane.

```yaml
netbird:
  policy:
    rules:
      - sources: ["team-infra-plat", "app:myapp"]
        protocol: tcp
        ports: ["443", "9090"]
```

- `destinations` is always the app's own NetBird group (`app-<app-name>`), created automatically by Terraform for every app directory.
- `sources` must be keys from the known group map: `team-infra-plat`, `team-sec-plat`, `github-actions`, `owners`, `sg-k8s-admin`, `all`, or `app:<name>` (colon-separated) for another app's group.
- If an app has no `netbird:` block, no policy is created for it (access is denied by default).
- Multiple rules in `policy.rules` produce separate `netbird_policy` resources named `app-<name>-0`, `app-<name>-1`, etc.

**Do not remove or treat this block as dead config** — it has no effect on Helm rendering but drives real infrastructure via Terraform.

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

The restic credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, etc.) live in a secret named `<app>-volsync-repo` in the app's namespace, synced from Infisical at `/k8s/volsync/<cluster-name>/<app>` via an `InfisicalSecret` CR in the app's `templates/secret.yaml`.

### Restore procedure

1. **Find the snapshot you want** (optional):
   ```bash
   hsctl volsync snapshot list <app>
   ```

2. **Scale down and enable restore** in `apps/<app>/app.yaml` For example, for omni:
   ```yaml
   clusters:
     mgmt:
       values:
         omni:
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

5. **Scale back up and disable restore** — remove both the scale down and `volsync.restore` override from `app.yaml` in one commit, push. ArgoCD syncs, deletes the `ReplicationDestination`, creates/recreates the `ReplicationSource`, and scales the deployment back up.
