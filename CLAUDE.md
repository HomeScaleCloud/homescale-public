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

This is enforced by `tests/test_runbooks.sh` (a `runbook-coverage` pre-commit hook, also run in CI): every repo-defined alert needs a `runbook_url` of the form above with a matching `docs/runbooks/<slug>.md` and `mkdocs.yml` nav entry, and every `docs/runbooks/*.md` must be claimed by an alert. The `<slug>` is taken from the `runbook_url` itself, so it doesn't have to be a mechanical kebab-case of the alert name.

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
tests/test_manifests.sh

# Run the hsctl/TOPF/bootstrap/update-cluster test suites (needs: pip install pytest ansible-core PyYAML;
# talosctl/ansible-playbook/openssl on PATH). Each suite is also its own CI matrix job.
pytest tests/test_hsctl.py tests/test_talos.py tests/test_bootstrap_cluster.py tests/test_update_cluster.py -v
```

Pre-commit runs automatically on commit (includes yamllint and detect-secrets among its hooks). CI runs pre-commit, a Trivy config scan, and a Helm render + kubeconform pass (`test_manifests.sh`) on every PR.

## Commit Convention

Conventional Commits are enforced by gitlint and CI:
```
type(scope): description
```
Types: `feat fix chore refactor docs style test perf ci build revert`

## Architecture

### GitOps Flow

ArgoCD on each cluster watches this repo. Each cluster has a bootstrap `apps.yaml` in `clusters/<cluster>/` that is an ArgoCD **app-of-apps**. That app-of-apps has two sources:
1. `clusters/<cluster>/` — recursively sync raw Kubernetes manifests, excluding only `topf.yaml`
2. `apps/` — the Helm chart that generates per-cluster ArgoCD Application objects

### App Catalog (`apps/`)

`apps/` is a Helm chart. `apps/templates/applications.yaml` loops over every `apps/*/app.yaml` and generates an ArgoCD `Application` for each app that is enabled for the current cluster.

Each `apps/<name>/app.yaml` controls deployment with these fields:
- `defaultDeploy: true|false` — whether to deploy to all clusters by default
- `path` — path to the actual Helm chart (required)
- `namespace` — target namespace (required)
- `syncWave` — ArgoCD sync wave; bootstrap order is: infisical (-35) → cert-manager/argocd/rbac (-30) → tailscale (-20) → external-dns (-10) → apps (0)
- `values` — Helm values passed through; may use `{{ .Values.env.name }}` and `{{ .Values.env.region }}` templating

Deployment overrides no longer live in `app.yaml`. Instead, `clusters/<cluster>/apps.yaml` (see below) carries an `apps:` map, keyed by app directory name, in its `apps` source's inline `helm.values` block:
- `apps.<app-name>.deploy: true|false` — per-cluster override of that app's `defaultDeploy`
- `apps.<app-name>.*` — any other field deep-merges over that app's base `app.yaml`, for this cluster only

```yaml
# clusters/production/apps.yaml, spec.sources[1].helm.values
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

- `clusters/<cluster>/apps.yaml` — the bootstrap ArgoCD app-of-apps (applied manually once); its directory source recursively syncs `clusters/<cluster>/` and excludes only `topf.yaml`. Generated Talos configs and credentials are gitignored
- `clusters/<cluster>/topf.yaml` is that cluster's TOPF inventory — see "Talos cluster provisioning" below

#### Talos cluster provisioning (TOPF, no Terraform)

Talos is managed by TOPF. Each clusters/<cluster>/topf.yaml holds version pins, SecureBoot schematic, endpoint, CIDRs and permanent node inventory. Shared native patches live in infra/topf/all and infra/topf/control-plane; TOPF automatically selects patches by role. Cluster data holds nodeSubnet, bondLinks, installDiskMatch, gateway and nameservers. The shared network patch defines bond1/LACP and VLANs 241/271, deriving each address from the node IP and subnet prefix. Node entries only need host, IP, role and optional labels or a disk override. host is a TOPF inventory alias; Talos HostnameConfig uses auto: stable without a static hostname, producing talos-… machine/Kubernetes names. Match Kubernetes nodes to inventory by InternalIP, not alias. There are no Helm libraries or generated machine configs to commit. Full rendered configs contain secrets and stay gitignored.

Use `hsctl run topf --cluster <name> <native TOPF arguments>`. Ordinary commands use a private cached secrets.yaml, restored from Infisical SECRETS_YAML at /k8s/talos/<prod|dev> in environment prod. Prefix --refresh-secrets to refresh, --init-secrets for explicit first initialization. Existing bundles are reused. New bundles must be backed up before use; failed uploads retain secrets.pending.yaml for retry. Never delete a bundle to repair authentication. Folders remain manually managed. CI uses a read-only bundle and never initializes a CA.

Local playbooks and TOPF use HSCTL_REPO_ROOT, including local changes. --git-ref is remote-only. TOPF generates short-lived client credentials from the CA; bootstrap makes a fresh admin kubeconfig each run. Default human access remains OIDC; --break-glass uses TOPF. hsctl get clusters discovers online Tailscale cluster tags and verifies API proxy reachability; normal kubeconfig selection requires that discovery. hsctl get nodes reads only the active kubectl context. Ansible inventory independently reads declared topf.yaml files and never calls Omni, Tailscale or kubectl.

First bootstrap is local: `hsctl run bootstrap-cluster --cluster <name> -e local --nodes <file>`, with unique {name, dhcp_ip, static_ip} entries for every control-plane node. Declare permanent addresses, the cluster install disk, node subnet, bond NICs, gateway and DNS in topf.yaml first. Offline render uses permanent network config; maintenance-mode apply targets DHCP; authenticated etcd bootstrap targets the first permanent address. Retry service installation without --nodes after Talos bootstrap succeeds. Private files are removed on success/failure.

Preserve bond1 (avoids the kernel bond0), LACP, VLANs 241/271, production's four NICs/VIP/role labels/Longhorn/Spegel, unique pod/service CIDRs, OIDC settings, Cilium prerequisites, schedulable control planes and kubelet cert rotation. Production's three control-plane install disks are /dev/nvme0n1, confirmed by the user after finding the NVMe selector in the historical boa1-prod config. Gateway and DNS still require confirmation; omitted values intentionally fail rendering. Do not invent hardware values. Production validation substitutes labeled temporary fixtures only for missing settings. CI applies default to disabled; set bootstrapComplete true only after local bootstrap, ArgoCD sync and Tailscale connectivity succeed.

Version bumps in topf.yaml are reconciled by infra/ansible/playbooks/update-cluster.yml: read-only native upgrade/config previews on affected PRs; every main deployment upgrades Talos with TOPF, Kubernetes with talosctl upgrade-k8s, verifies all running versions, then applies remaining config. Clusters run serially in sorted order, and any failure stops the run. Requires data.bootstrapComplete true after local bootstrap. Rejects downgrades/minor skips; native preflight stays enabled. If Kubernetes requires newer Talos, merge a Talos-only PR first. Ordinary TOPF apply can bypass Kubernetes orchestration; use update-cluster for version changes. Renovate tracks Talos/Kubernetes/TOPF separately with no automatic merges.

See docs/architecture/clusters.md and docs/operations/registering-machines.md for authoritative instructions. Use matching Image Factory SecureBoot media and verify securitystate in maintenance mode. Never commit credentials or full generated node configs.

### Infrastructure (`infra/`)

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, Tailscale ACL/tags). State is in Terraform Cloud (`homescale` org, `homescale` workspace). `infra/terraform/plan-apply.sh` is the shared plan/apply logic CI's `terraform` job and `hsctl run terraform -e local` both call.
- `infra/ansible/` — Bootstrapping playbooks (e.g., workload cluster bootstrap), run by CI's `ansible` job or `hsctl run <playbook> -e local`
- `infra/topf/` — shared native Talos patches and Infisical secrets provider (TOPF pin lives in the tool installer). Cluster inventory lives in clusters/<cluster>/topf.yaml.

### Secrets

Infisical is the secrets store. The Infisical k8s operator (deployed as an ArgoCD app with syncWave -35) syncs secrets from Infisical into cluster namespaces. No secrets belong in this repo — the `detect-secrets` pre-commit hook will catch them. The `# pragma: allowlist secret` comment suppresses false positives on non-secret strings like secret names.

### CI/CD Pipelines

Build, scan and test run in parallel; deploy and mirror require all three to pass. The Python test suites share a matrix job in `test.yaml`, retaining their individual check names.

Workflows called from `ci.yaml`:
- **scan** — pre-commit, PR title lint (Conventional Commits), CodeQL, Trivy config scan
- **build** — builds only changed apps on PRs and on pushes to main (all apps on a published release), builds Docker images, runs Trivy image scan; Helm charts are linted but not published
- **deploy** (`terraform` → `update-cluster` → `ansible`) — public-service Terraform plans/applies, Ansible-orchestrated Talos/Kubernetes upgrades and config reconciliation for existing clusters, and manually dispatched Ansible bootstrap services. Cluster playbooks join Tailscale to reach existing clusters. First cluster bootstrap runs from the LAN. TOPF requires data.bootstrapComplete true and an existing read-only CA bundle. PR dry-run exit 2 means drift, not failure. Required status display labels scan / Talm and deploy / Talm Gate are retained for the GitHub ruleset, but run TOPF checks.
- **ansible** — dispatched playbooks generate a fresh short-lived kubeconfig from Infisical SECRETS_YAML; they do not use a stored KUBECONFIG. --nodes is local-only.

`bootstrap-cluster` is for initial setup and skips clusters marked bootstrapComplete. `update-cluster` handles ongoing reconciliation: versions, TOPF configuration, and ArgoCD/Infisical service credentials. Both playbooks reuse the cluster's Infisical login in CI; hsctl fetches local service credentials into a private extra-vars file. Update previews use Kubernetes check mode with secret values/diffs suppressed. Full version convergence is checked before config apply, which retains TOPF's native health/stabilization checks.

### Networking

Tailscale is the zero-trust mesh used for human and machine access to services — CI reaching internal infra, and service exposure to end users.
CI joins the tailnet as an ephemeral node (`tailscale/github-action`, tagged `tag:github-actions`, removed when the job completes) in the `ansible` job, to reach a cluster's apiserver for `bootstrap-cluster`. `terraform` (the general workspace) never joins — it only calls public APIs. `tag:github-actions` is also a valid `sources` identifier any app's own `tailscale:` policy block can grant access to (see below) — currently no app does.

**LAN reachability — per-cluster subnet routers.** There is no standalone/dedicated subnet-router device; each cluster runs its own, in-cluster, as part of the `tailscale` app — a `Connector` resource (`apps/tailscale/templates/connector-subnet-router.yaml`, rendered only when `.Values.subnetRouter.advertiseRoutes` is set) advertising the LAN its own nodes physically sit on, declared per cluster as `nodeSubnet` in `clusters/<cluster>/topf.yaml` and mirrored into that cluster's `apps.yaml` override (`apps.tailscale.values.subnetRouter.advertiseRoutes` — the two can't share one source: Terraform reads `topf.yaml` data directly via `yamldecode`, but `apps.yaml` is what Helm/ArgoCD actually renders into the live `Connector`). Each cluster is on its own VLAN/subnet: `production` on `10.1.245.0/24`, `development` on `10.1.247.0/24`.

This is **not** available until a cluster has already bootstrapped and synced once (ArgoCD has to deploy the `tailscale` app before its `Connector` can advertise anything) — see "Bootstrap: adding a new cluster" in `docs/architecture/clusters.md` for what that means for a brand-new cluster's first apply. This is also why a brand-new cluster's first `bootstrap-cluster` run is always local — nothing is reachable over Tailscale until after that first sync.

Terraform's `tailscale` module reads every `clusters/*/topf.yaml` (`data.nodeSubnet`, `data.podSubnets`, `data.serviceSubnets`) to (a) auto-approve those routes (`autoApprovers.routes` in `acl.tf` — otherwise every advertised route needs manual approval in the Tailscale admin console) and (b) grant access to them: `nodeSubnet` (the LAN) is reachable by `group:sg-k8s-admin@REDACTED` and `tag:github-actions` (`local.lan_grants`); `podSubnets`/`serviceSubnets` are reachable by `sg-k8s-admin` only (`local.pod_service_grants`) — nothing else gets either, by design. `podSubnets`/`serviceSubnets` must be unique across clusters for this to mean anything (two clusters can't both claim the same destination CIDR on one tailnet) — `scan/Talm` CI fails if they ever collide.

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
- `local.lan_grants` — each cluster's advertised LAN subnet(s) (`local.cluster_advertise_routes`, read from every `clusters/*/topf.yaml`'s `data.nodeSubnet`, deduped), for `sg-k8s-admin` and `tag:github-actions` only (`ip: ["*"]`) — see Networking above. Empty (no grant at all) until at least one cluster declares a route.
- `local.pod_service_grants` — each cluster's `podSubnets`/`serviceSubnets` (`local.cluster_pod_service_routes`, read the same way), for `sg-k8s-admin` only (`ip: ["*"]`) — see Networking above. Also empty until a cluster declares one.

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
