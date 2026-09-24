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
helm template apps -f apps/values.yaml --set cluster.name=mgmt

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

One directory per cluster. The set of clusters changes often — read `clusters/` for the current list rather than relying on any list here. Cluster names follow the `<region>-<name>` convention (e.g. `boa1-prod`); `mgmt` is the exception. Each cluster maps to exactly one region.

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

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, Tailscale ACL/tags, mgmt cluster bootstrap). State is in Terraform Cloud (`homescale` org, `homescale` workspace).
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
- `local.omni_k8s_grant` — the Omni Kubernetes proxy (`dst: tag:omni-k8s`, Omni's `k8s` Service at `REDACTED`) on `tcp:443`, restricted to `group:sg-k8s-admin@REDACTED` only (PIM activation required). This endpoint is deliberately **not** covered by omni's `tag:app-omni` policy (which gates the Omni UI/API) — it's the Talos/Omni kube proxy, break-glass human access only. Automatron, which also fetches per-cluster kubeconfigs through this same proxy, doesn't need this grant at all — it reaches Omni entirely in-cluster (same `mgmt` cluster), not over Tailscale; see [Automatron](#automatron-ansible-cluster-bootstrap--omni-sync). A Tailscale-exposed Service reaches this grant by carrying `tag:omni-k8s` (allowed by the kyverno annotation policy alongside `tag:app-*` and `tag:k8s-api`) instead of `tag:app-<name>`.

## Automatron (Ansible cluster bootstrap + Omni sync)

`apps/automatron` (syncWave 0, `mgmt` only) is the in-cluster runner for `infra/ansible/playbooks/`. It replaced two GitHub Actions jobs (`ansible`, and the state-changing half of `omni`) — that work now runs inside the cluster it's bootstrapping instead of on billed GH-hosted runners.

- Three CronJobs, one per playbook, sharing one pod spec (`templates/_pod.tpl`):
  - `automatron-omni-sync` — **the only one that actually fires on its own** (every 5 minutes). Runs `omni-sync.yml`, syncing every `clusters/*/cluster.yaml` and `infra/omni/machineclasses/*.yaml` into Omni. On success (and unless `dry_run` is set), it chains a Job cloned from `automatron-bootstrap-cluster`'s `jobTemplate`, named `automatron-bootstrap-cluster-<timestamp>` (see `CHAIN_NEXT_CRONJOB` in `_pod.tpl`/`entrypoint.sh`) — so clusters always exist in Omni before bootstrap-cluster runs against them, without relying on schedule offsets. A `REDACTED/chained-from` label plus an active-Job lookup (needs the `job-operator` ClusterRole's `get`/`list` on `jobs`) skips chaining another one if a previous chained run is still active, since the timestamped name no longer gives that dedup for free the way a fixed name did.
  - `automatron-bootstrap-cluster` — `suspend: true`, never auto-fires. Only ever runs via that chain, or ad hoc.
  - `automatron-bootstrap-mgmt` — `suspend: true`, never auto-fires (mgmt changes rarely). Ad hoc only.
  - The suspended two exist purely so `hsctl run <playbook> -e remote` has a `jobTemplate` to clone — see below.
- Each run's pod: `git-key-prep` initContainer (root — see below) → `git-clone` (`git-sync` image in one-time mode, checks out `main` via SSH) → `automatron` container (ansible-core/kubectl/helm/omnictl/envsubst baked into the image, running as a non-root user; ansible collections installed at start from the git-cloned `requirements.yml`).
- **No Tailscale anywhere in this app** — Omni lives in the same cluster (`mgmt`), so automatron reaches it entirely in-cluster. `_pod.tpl` sets `hostAliases` pointing `REDACTED`/`REDACTED` at the real ClusterIPs of `apps/omni`'s `api`/`k8s` Services (via Helm's `lookup`, which only resolves against a live cluster — offline rendering, e.g. `validate-manifests.sh`, falls back to a dummy `0.0.0.0` so it still renders), so `OMNI_ENDPOINT` and the rest of the ansible/omnictl config need no changes at all — same hostnames, same real cert, just resolved differently. `omni_k8s_grant` in `acl.tf` is back to `sg-k8s-admin`-only (break-glass) now that nothing else needs Tailscale access to Omni's k8s-proxy.
- Automatron's own credentials are mostly *reused*, not re-provisioned, since identities/service accounts are billed or administratively heavier than plain secrets: its Infisical login reuses the k8s Infisical Operator's own identity (`INFISICAL_OPERATOR_CLIENT_ID`/`_SECRET` at `/k8s/infisical`, synced via the `automatron-infisical-operator-creds` CR), and `GIT_DEPLOY_KEY` in `/k8s/automatron` is an Infisical secret *reference* pointing at the same value as `/k8s/argocd/deploy-key`'s `sshPrivateKey`, not a separately-minted key. Its Omni access (`OMNI_SERVICE_ACCOUNT_KEY`) lives directly in `/k8s/automatron` alongside those, synced by the same `automatron-secrets` CR as everything else there — no dedicated CR, and no longer tied to the `omni` CI job's `/github-actions` credential the way it originally was. `git-key-prep` runs as root because secret-mounted files come out root-owned at mode `0600` (required — sshd's strict key-perm check rejects any group/other bits); it copies the key into a writable volume (restoring a trailing newline the stored value is missing, which OpenSSH's parser needs) and hands ownership to `git-clone`'s actual non-root UID, so `git-clone` itself doesn't need root.
- `bootstrap-mgmt`/`cluster-secrets` still separately read `/k8s/argocd/deploy-key` and `/k8s/infisical` at runtime — that's automatron *propagating* ArgoCD's/the k8s-operator's own credentials into whatever cluster it's bootstrapping, unrelated to the reuse above.
- `MGMT_KUBECONFIG` (mgmt is Vultr VKE, reached over the public internet — no Tailscale needed for `bootstrap-mgmt`, or for the `deploy.yaml` Sync step below) is Terraform-managed, under `/k8s/automatron`.
- Ad hoc / on-demand runs: `hsctl run <playbook> -e remote [--dry-run]` (see `docs/operations/hsctl.md`) clones the relevant CronJob's `jobTemplate` into a one-off `Job` and streams its logs; `--dry-run` (only `omni-sync` acts on it) also suppresses the chain-into-bootstrap-cluster. `team-infra-plat`/`team-sec-plat` can do this without PIM (`job-operator` ClusterRole in `apps/rbac`, also bound to automatron's own ServiceAccount for its self-chaining); log reading already worked via the existing `pod-operator` binding.
- `deploy.yaml`'s `omni` job: the PR-time dry-run + per-cluster/machineclass comment functionality is unchanged (still calls `omnictl` directly — it's read-only and diff-scoped, not worth routing through automatron). Only the merge-to-`main` **Sync** step changed: it now builds a `mgmt` kubectl context from `MGMT_KUBECONFIG` and runs `./hsctl run omni-sync -e remote`, so the actual state-changing sync (and, via the chain above, the bootstrap-cluster run after it) happens on automatron with its logs streamed straight into the GitHub Actions log — not executed directly on the runner.

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
   hsctl get snapshot <app>
   ```

2. **Scale down and enable restore** in `clusters/<cluster>/apps.yaml`'s `apps` source values. For example, for omni on `mgmt`:
   ```yaml
   # clusters/mgmt/apps.yaml, spec.sources[1].helm.values
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
