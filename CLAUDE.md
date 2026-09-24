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

Runbooks live under `docs/runbooks/` grouped by system (e.g. Omni alerts → `omni-*.md`, PDU alerts → `apc-pdu-*.md`). See existing runbooks for the expected format: header with severity/alert/dashboard, "What this means" section, "Common causes" table, remediation steps. No "Diagnosis" section — the alert firing is the diagnosis.

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
helm template apps -f apps/values.yaml --set cluster.name=core

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
# clusters/boa1-prod/apps.yaml, spec.sources[1].helm.values
cluster:
  name: boa1-prod
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

One directory per cluster. The set of clusters changes often — read `clusters/` for the current list rather than relying on any list here. Cluster names follow the `<region>-<name>` convention (e.g. `boa1-prod`); `core` is the exception. Each cluster maps to exactly one region.

- `clusters/<cluster>/apps.yaml` — the bootstrap ArgoCD app-of-apps (applied manually once)
- `clusters/<cluster>/cluster.yaml` — Omni cluster template (Talos/k8s versions, machine assignments, patches); uses `$CLUSTER_NAME` envsubst substitution at deploy time

#### Registering new machines with Omni

A machine must be registered with Omni before it can be added to a `cluster.yaml` `machines:` list:

1. Log in to Omni (`https://REDACTED`), click **Download Installation Media**, and build a schematic (arch, system extensions matching the target cluster's `systemExtensions`, Secure Boot on/off).
2. Write the downloaded ISO to a USB drive (`dd if=<iso> of=/dev/<device> conv=fdatasync`) or mount it as virtual media via the server's BMC (iDRAC/iLO/IPMI).
3. Boot the machine from it — Talos boots into maintenance mode and needs outbound access to Omni's WireGuard port (or TCP 443 for HTTP/2 tunneling).
4. It appears in Omni's **Machines** list shortly after boot, identified by its Talos/SMBIOS UUID, in an unallocated state.
5. Add that UUID to the relevant `machines:` list in `clusters/<cluster>/cluster.yaml` and merge — CI's Omni template sync claims the machine and installs the cluster onto it.

Full walkthrough: `docs/operations/registering-machines.md`.

### Infrastructure (`infra/`)

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, Tailscale ACL/tags, core cluster bootstrap). State is in Terraform Cloud (`homescale` org, `homescale` workspace).
- `infra/ansible/` — Bootstrapping playbooks (e.g., Omni bootstrap)
- `infra/omni/patches/` — shared Talos machine config patches applied to clusters during Omni template sync

### Secrets

Infisical is the secrets store. The Infisical k8s operator (deployed as an ArgoCD app with syncWave -35) syncs secrets from Infisical into cluster namespaces. No secrets belong in this repo — the `detect-secrets` pre-commit hook will catch them. The `# pragma: allowlist secret` comment suppresses false positives on non-secret strings like secret names.

### CI/CD Pipelines

Three reusable workflows called from `ci.yaml`:
- **scan** — pre-commit, PR title lint (Conventional Commits), CodeQL, Trivy config scan
- **build** — builds only changed apps on PRs and on pushes to main (all apps on a published release), builds Docker images, runs Trivy image scan; Helm charts are linted but not published
- **deploy** — Terraform plan (PR) / apply (main), then Omni plan (PR: dry-run + PR comments) / sync (main: dispatched to automatron, not run on the runner) for changed clusters; the `omni` job connects to internal infrastructure via an ephemeral Tailscale node (`tailscale/github-action`, tagged `tag:github-actions`); `terraform` doesn't need mesh access at all — it only talks to public APIs. Ansible cluster bootstrap no longer runs here at all — see [Automatron](#automatron-ansible-cluster-bootstrap--omni-sync)

### Networking

Tailscale is the zero-trust mesh used for human and machine access to services — CI reaching internal infra, and service exposure to end users.
CI jobs that need internal infra (Omni) join the tailnet as an ephemeral node (`tailscale/github-action`, tagged `tag:github-actions`, auto-removed when the job ends); Terraform doesn't need mesh access since it only calls public APIs.

**Internal service exposure** — the `tailscale` app deploys the official Tailscale Kubernetes Operator plus a shared per-cluster ingress `ProxyGroup` to every cluster. A Service opts in with `type: LoadBalancer` / `loadBalancerClass: tailscale`, annotated `tailscale.com/tags`/`tailscale.com/hostname`/`tailscale.com/proxy-group: ingress` (routes through the shared ProxyGroup instead of a dedicated proxy pod) and `external-dns.kubernetes.io/hostname` for a friendly `<name>.<cluster>REDACTED` CNAME, published by `external-dns` running in every cluster.

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
- `local.k8s_grant` — workload-cluster apiserver proxies (`dst: tag:k8s-api`, the `tailscale` app's `kube-apiserver-proxy` Service) on `tcp:443`, for Infrastructure Platforms, Security Platforms, `sg-k8s-admin`, and `tag:app-headlamp`.
- `local.omni_k8s_grant` — the Omni Kubernetes proxy (`dst: tag:omni-k8s`, Omni's `k8s` Service at `REDACTED`) on `tcp:443`, restricted to `group:sg-k8s-admin@REDACTED` only (PIM activation required). This endpoint is deliberately **not** covered by omni's `tag:app-omni` policy (which gates the Omni UI/API) — it's the Talos/Omni kube proxy, break-glass human access only. Automatron, which also fetches per-cluster kubeconfigs through this same proxy, doesn't need this grant at all — it reaches Omni entirely in-cluster (same `core` cluster), not over Tailscale; see [Automatron](#automatron-ansible-cluster-bootstrap--omni-sync). A Tailscale-exposed Service reaches this grant by carrying `tag:omni-k8s` (allowed by the kyverno annotation policy alongside `tag:app-*` and `tag:k8s-api`) instead of `tag:app-<name>`.

## Automatron (kro-backed job runner + Ansible/script execution)

`apps/automatron` (syncWave 0, `core` only) is the in-cluster runner for `infra/ansible/playbooks/` (and, for `script`-runner templates, arbitrary bash/python under `infra/automatron/scripts/`). It replaced two GitHub Actions jobs (`ansible`, and the state-changing half of `omni`) — that work now runs inside the cluster it's bootstrapping instead of on billed GH-hosted runners.

- What used to be hand-written Helm `CronJob` templates (`templates/_pod.tpl`'s `include`/`dict` boilerplate) is now a plain CRD interface, backed by [kro](https://kro.run) (`apps/kro`, syncWave -25, `core` only — installs the kro controller + its `ResourceGraphDefinition` CRD). Two `ResourceGraphDefinition`s in `apps/automatron/templates/` (`rgd-jobtemplate.yaml`, `rgd-jobrun.yaml`) define the actual `REDACTED/v1alpha1` CRDs — both cluster-scoped (single automatron install per cluster, no per-namespace isolation needed) and carry `additionalPrinterColumns` so `kubectl get jobtemplate`/`jobrun` show useful state instead of the generic Age-only default:
  - **`JobTemplate`** — one playbook (`spec.playbook`) or script (`spec.scriptPath`/`spec.scriptInterpreter`), optionally `spec.schedule`d (kro creates a `CronJob` when set — `includeWhen` on the schedule field, no `suspend: true` trick needed). Omitting `schedule` makes it template-only, runnable only via a `JobRun`.
  - **`JobRun`** — a one-off instance of a `JobTemplate`. This is the *only* place a one-off `Job` ever gets created from a template: a human commits one under `infra/automatron/job-runs/`, `hsctl run <template> [--chain ...] -e remote` creates one ad hoc, or chaining (below) creates one for each subsequent hop. It resolves its `JobTemplate` via a kro `externalRef` whose lookup name is a CEL expression over the `JobRun`'s own `spec.templateRef` (not a static name) — if this dynamic lookup ever stops resolving, the fallback is having `JobRun` carry its own `playbook`/`scriptPath` fields directly instead of inheriting them. `status.phase` (`Pending`/`Running`/`Succeeded`/`Failed`) is projected from the underlying `Job`'s own status via CEL.
  - The pod boilerplate (serviceAccount, volumes, `git-key-prep`/`git-clone`/`omni-hosts` initContainers, base container) is duplicated across the two RGDs — kro has no Helm-`include`-equivalent for sharing a template fragment across `ResourceGraphDefinition`s. Keep them in sync by hand when changing shared pod shape.
- Instances (the things you actually commit) live under `infra/automatron/`, synced by its own standalone ArgoCD Application (`clusters/core/automatron-jobs.yaml`) rather than as a source on `apps-core` — deliberately independent, so a pending `REDACTED` CRD (before kro's reconciled the RGDs) can't block `apps-core`'s own multi-source sync, which would otherwise deadlock atomically (confirmed live — see git history on `clusters/core/apps.yaml` and `clusters/core/automatron-jobs.yaml`). Subdirs: `job-templates/`, `job-runs/` (rare — most runs are ad hoc), `scripts/`. `.github/scripts/validate-manifests.sh` conforms this tree directly (no Helm rendering involved), scanning every `Application` manifest under `clusters/<cluster>/`, not just `apps.yaml`. See `docs/operations/hsctl.md`'s "Automatron job CRDs" section for the field reference and examples.
- Chaining (`spec.chain` on both CRDs — a comma-separated list of `JobTemplate` names to run, in order, after this one succeeds): `entrypoint.sh` reads `CHAIN_JOBS` (set from `spec.chain`) and, on success, creates a `JobRun` for the first name in the list, carrying the *rest* of the list as that `JobRun`'s own `spec.chain` — walking the list one hop at a time. `CHAIN_ROOT` threads a stable identity through every hop of one chain (defaults to the first `JobRun`'s own name; a scheduled `JobTemplate`'s first hop has no backing `JobRun`, so it reads its own Job's name via the downward API's `job-name` pod label instead), used only to label each hop's `Job` for `hsctl run --chain`'s log-following and for a same-template active-Job dedup guard (`concurrencyPolicy: Forbid` doesn't cover Jobs created this way). This is exactly the old single-hop `CHAIN_NEXT_CRONJOB` mechanism, generalized to a list — kro's `forEach`/collections can't express "step N waits for step N-1" (collection items are independent), so sequencing stays bash-driven, not kro-managed. Migrated default: `job-templates/omni-sync.yaml` (`schedule: "*/15 * * * *"`, `chain: bootstrap-cluster`) — clusters always exist in Omni before bootstrap-cluster runs against them.
- Each run's pod: `git-key-prep` initContainer (root, on automatron's own image running `git-key-prep.sh` — see below) → `git-clone` (`git-sync` image in one-time mode, checks out `main` via SSH) → `automatron` container (ansible-core/kubectl/helm/omnictl/envsubst baked into the image, running as a non-root user; ansible collections installed at start from the git-cloned `requirements.yml`). `entrypoint.sh` picks `ansible-playbook` vs. the raw script based on which of `PLAYBOOK`/`SCRIPT_PATH` is set (exactly one must be).
- **No Tailscale anywhere in this app** — Omni lives in the same cluster (`core`), so automatron reaches it entirely in-cluster. Each RGD's pod template sets `hostAliases` pointing `REDACTED`/`REDACTED` at the real ClusterIPs of `apps/omni`'s `api`/`k8s` Services (resolved at pod start by the `omni-hosts` initContainer, not via Helm's `lookup`, which ArgoCD's renders have been observed returning empty for), so `OMNI_ENDPOINT` and the rest of the ansible/omnictl config need no changes at all — same hostnames, same real cert, just resolved differently. `omni_k8s_grant` in `acl.tf` is `sg-k8s-admin`-only (break-glass) since nothing else needs Tailscale access to Omni's k8s-proxy.
- Automatron's own credentials are mostly *reused*, not re-provisioned, since identities/service accounts are billed or administratively heavier than plain secrets: its Infisical login reuses the k8s Infisical Operator's own identity (`INFISICAL_OPERATOR_CLIENT_ID`/`_SECRET` at `/k8s/infisical`, synced via the `automatron-infisical-operator-creds` CR), and `GIT_DEPLOY_KEY` in `/k8s/automatron` is an Infisical secret *reference* pointing at the same value as `/k8s/argocd/deploy-key`'s `sshPrivateKey`, not a separately-minted key. Its Omni access (`OMNI_SERVICE_ACCOUNT_KEY`) lives directly in `/k8s/automatron` alongside those, synced by the same `automatron-secrets` CR as everything else there — no dedicated CR, and no longer tied to the `omni` CI job's `/github-actions` credential the way it originally was. `git-key-prep` (`apps/automatron/git-key-prep.sh`, baked into the automatron image) runs as root because secret-mounted files come out root-owned at mode `0600` (required — sshd's strict key-perm check rejects any group/other bits); it copies the key into a writable volume (restoring a trailing newline the stored value is missing, which OpenSSH's parser needs) and hands ownership to `git-clone`'s actual non-root UID, so `git-clone` itself doesn't need root.
- `bootstrap-core`/`cluster-secrets` still separately read `/k8s/argocd/deploy-key` and `/k8s/infisical` at runtime — that's automatron *propagating* ArgoCD's/the k8s-operator's own credentials into whatever cluster it's bootstrapping, unrelated to the reuse above.
- `CORE_KUBECONFIG` (core is Vultr VKE, reached over the public internet — no Tailscale needed for `bootstrap-core`, or for the `deploy.yaml` Sync step below) is Terraform-managed, under `/k8s/automatron`.
- Ad hoc / on-demand runs: `hsctl run <name> [--chain <name>[,...]] -e remote [--dry-run] [--cluster <name>]` (see `docs/operations/hsctl.md`) applies a `JobRun` CR and streams the resulting `Job`'s logs — `--chain` follows every subsequent hop's logs too, as `entrypoint.sh` creates each one in turn. `team-infra-plat`/`team-sec-plat` can do this without PIM (`job-operator` ClusterRole in `apps/rbac`, with `create`/`get`/`list` on `REDACTED` `jobruns` and `get`/`list` on `jobtemplates`, also bound to automatron's own ServiceAccount for its self-chaining); log reading already worked via the existing `pod-operator` binding.
- `deploy.yaml`'s `omni` job: the PR-time dry-run + per-cluster/machineclass comment functionality is unchanged (still calls `omnictl` directly — it's read-only and diff-scoped, not worth routing through automatron). Only the merge-to-`main` **Sync** step changed: it now builds a `core` kubectl context from `CORE_KUBECONFIG` and runs `./hsctl run omni-sync --chain bootstrap-cluster -e remote`, so the actual state-changing sync *and* the bootstrap-cluster run after it happen on automatron with both steps' logs streamed straight into the GitHub Actions log in turn — not executed directly on the runner.

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

The restic credentials (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, etc.) live in a secret named `<app>-volsync-repo` in the app's namespace, synced from Infisical at `/k8s/volsync/<cluster-name>/<app>` via an `InfisicalSecret` CR in the app's `templates/secret.yaml`. Since that repository path is derived from the deploying cluster's own `.Values.cluster.name`, restoring into a cluster under a different name than the one the backup was written under (e.g. after a rename, or standing up a replacement cluster) needs an explicit `volsync.restore.sourceCluster` override — otherwise it resolves to a fresh, empty path under the new name instead of the old backup data. `apps/omni/templates/secret.yaml` implements this (`{{ (((.Values.volsync).restore).sourceCluster) | default .Values.cluster.name }}`); other apps' `secret.yaml` would need the same pattern added before they could use it. It's a one-time bootstrap workaround, not a standing feature — remove the `sourceCluster` override (along with `restore.enabled`) once the restore is confirmed, so ongoing backups resume writing under the cluster's real name.

### Restore procedure

1. **Find the snapshot you want** (optional):
   ```bash
   hsctl get snapshot <app>
   ```

2. **Scale down and enable restore** in `clusters/<cluster>/apps.yaml`'s `apps` source values. For example, for omni on `core`:
   ```yaml
   # clusters/core/apps.yaml, spec.sources[1].helm.values
   apps:
     omni:
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

5. **Scale back up and disable restore** — remove both the scale down and `volsync.restore` override from `clusters/<cluster>/apps.yaml` in one commit, push. ArgoCD syncs, deletes the `ReplicationDestination`, creates/recreates the `ReplicationSource`, and scales the deployment back up.
