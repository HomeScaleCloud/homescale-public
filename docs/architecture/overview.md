# Architecture Overview

HomeScale uses a full GitOps model: **this repository is the source of truth** for every cluster. Nothing is applied manually except the one-time bootstrap. All ongoing changes flow through pushes to the `main` branch.

## GitOps loop

There are two independent reconciliation paths from `main`:

### Path 1 — CI (push-based, triggered on merge)

```
PR merged to main
       │
       ├─► scan ──────────────────── YAML lint, secrets scan, CodeQL, Trivy
       │
       ├─► build ─────────────────── Docker images → ghcr.io/homescalecloud/<name>
       │                             MkDocs → GitHub Pages (REDACTED)
       │
       └─► deploy
              │
              ├─► terraform apply ── Cloudflare DNS, Tailscale ACL/tags,
              │                      Infisical project structure, VolSync secret paths,
              │                      Vultr (core cluster)
              │
              └─► omni sync ──────── cluster.yaml → Omni (Talos node config,
                                     k8s version, machine assignments)
```

### Path 2 — ArgoCD (pull-based, continuous)

```
Git (main)
    │  ▲ polls every 30s
    │  │
    ▼  │
ArgoCD (on each cluster)
    │
    ├── Source 1: clusters/<cluster>/   raw Kubernetes manifests
    │
    └── Source 2: apps/                 Helm chart → one ArgoCD Application per enabled app
                                                │
                                                └─► syncs apps/<name>/ charts to cluster
```

These two paths are independent. CI handles infrastructure and Talos cluster config; ArgoCD handles every Kubernetes workload. App-only changes (editing `app.yaml`, chart templates, values) are picked up by ArgoCD once merged into the `main` branch without any CI deploy step.

## Secrets

```
Infisical (SaaS)
    │
    │  Infisical k8s operator (syncWave -35)
    │  watches InfisicalSecret CRs in each namespace
    ▼
Kubernetes Secrets  ──►  consumed by app pods as env vars / mounted files
```

Each app that needs secrets defines an `InfisicalSecret` CR in its Helm chart pointing at a path in Infisical (e.g. `/k8s/<namespace>/<app>`). The operator syncs them into the cluster at runtime — no secrets are stored in this repo. See [Secrets](secrets.md) for details.

## Observability

```
Every cluster
    │  kube-prometheus-stack (per-cluster)
    │  scrapes: node-exporter, kube-state-metrics, app ServiceMonitors
    │
    │  remote-write (via Tailscale)
    ▼
Prometheus Aggregator  ──  boa1-prod (metrics namespace)
    │
    ├──► Grafana        dashboards at REDACTED
    ├──► Alertmanager   fires to #alerts-infra-plat Slack channel
    │                   alert title links to runbook
    └──► Loki           log aggregation from all clusters via Grafana Alloy
```

Prometheus on each cluster retains 2 hours of data and remote-writes everything to the central instance, which carries the `cluster` external label. Grafana, Alertmanager, and the aggregated Prometheus/Loki instances each run as a single instance on a designated prod cluster. See [alert runbooks](../runbooks/index.md) for configured alerts.

## App catalog (`apps/`)

`apps/` is a Helm chart. `apps/templates/applications.yaml` loops over every `apps/*/app.yaml` using Helm `fileset` + `fromYaml` and generates an ArgoCD `Application` for each app that is enabled for the current cluster.

### Enabling / disabling apps per cluster

Each `app.yaml` has a `defaultDeploy` boolean. Deployment overrides live separately, in `clusters/<cluster>/apps.yaml`'s inline Helm values, under an `apps:` map keyed by app name:

```yaml
# apps/my-app/app.yaml
defaultDeploy: false        # don't deploy everywhere by default
```

```yaml
# clusters/boa1-prod/apps.yaml, spec.sources[1].helm.values
apps:
  my-app:
    deploy: true            # enable only on this cluster
    values:
      replicaCount: 3       # deployment override (deep-merged)
```

See the [App reference](apps.md) for the full field list.

### Apps built in CI

Any app directory that contains both a `Chart.yaml` and a `Dockerfile` is treated as a first-party image. CI builds it on every merge to `main` and pushes to `ghcr.io/homescalecloud/<name>`.

## Cluster topology

| Type | Kind | Role |
|------|------|------|
| `core` | Vultr Kubernetes Engine (VKE) | Single management cluster. Hosts Omni, ArgoCD, Infisical operator, and shared infrastructure. Provisioned by Vultr via Terraform. |
| `<region>-*` | Talos (Omni-managed) | General compute clusters for production workloads. |

Talos clusters have their node config, k8s version, and machine assignments managed entirely by Omni, which runs on the `core` cluster. The CI deploy workflow syncs `clusters/<name>/cluster.yaml` to Omni on every merge to `main`.

## Sync wave order

[ArgoCD sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) control the ordering of app deployments on a cluster. Lower wave numbers sync first.

| Wave | Apps | Why first |
|------|------|-----------|
| -40 | `cilium` | CNI must be ready before any other pod can schedule |
| -35 | `infisical`, `multus` | Secrets operator must be ready so other apps can pull secrets; Multus for multi-homed pods |
| -30 | `cert-manager`, `argocd`, `rbac` | TLS, GitOps and access control |
| -25 | `generic-device-plugin-tun`, `node-inotify-limits`, `kro` | Node resource registration and sysctl tuning before consumers; kro's CRDs must exist before automatron's JobTemplate/JobRun/JobWorkflow/JobWorkflowRun instances |
| -20 | `tailscale`, `spegel` | Mesh access and network routing before services need them |
| -10 | `external-dns`, `kubelet-serving-cert-approver` | DNS registration before apps |
| -5 | `volsync` | Backup operator ready before app PVCs need it |
| 0 | everything else | Default wave |
| 1+ | apps that depend on wave-0 apps | |

## CI/CD pipeline

Four reusable workflows are called from `.github/workflows/ci.yaml`: `scan`, `build`, `deploy`, and `mirror` (mirrors the repo to a public read-only remote on push; not covered further here).

`ci.yaml` runs on every PR and every push to `main`, and also on a published GitHub release. A release run executes `build` only (to rebuild every app image) — `deploy` and `mirror` are skipped.

### `scan` — security and lint

Runs on every PR and push:

- [`pre-commit`](https://pre-commit.com/) — YAML lint, trailing whitespace, detect-secrets, Helm lint
- PR title validation against [Conventional Commits](https://www.conventionalcommits.org/) (enforced by a regex check; only runs on PRs)
- [Trivy](https://trivy.dev/) — config scan for misconfigurations in Kubernetes manifests (table output in the job log; CRITICAL/HIGH findings fail the job)

### `build` — Docker images and docs

- Builds only the `apps/*/` directories that changed — on PRs (versus the base branch) and on pushes to `main` (versus the previous commit). A published GitHub release rebuilds every app.
- Builds the `Dockerfile` if present, tags with both `<git-sha>` and `latest`, pushes to `ghcr.io/homescalecloud/<name>`
- Runs a Trivy vulnerability scan on each built image (CRITICAL/HIGH, blocks on failure)
- **Deploys this documentation site** to GitHub Pages (`mkdocs gh-deploy`) on every push to `main`

### `deploy` — infrastructure and cluster sync

Runs on every PR and push to `main` (after `scan` and `build` pass), serialized repo-wide via a `concurrency: deploy` group so overlapping runs queue instead of racing. It has two sequential jobs — `terraform` → `omni`. Neither joins the tailnet — `terraform` only talks to public APIs (Cloudflare, Vultr, Infisical, Tailscale), and `omni` reaches Omni entirely through automatron (a `core` kubectl context via `CORE_KUBECONFIG`), not directly.

#### 1. `terraform`

- **On PR**: runs `terraform plan` and posts the plan diff as a PR comment
- **On merge to `main`**: runs `terraform apply` (gated by a GitHub Environment) — manages Cloudflare DNS, Vultr, Infisical project structure, Tailscale ACL and tags, VolSync secret paths, etc

#### 2. `omni` (after terraform)

Detects changed `clusters/<name>/cluster.yaml` and `infra/omni/machineclasses/*.yaml` files. Both the PR-time plan and the merge-time sync dispatch to automatron in `core` rather than running `omnictl` on the runner directly — this job only ever needs a `core` kubectl context (`CORE_KUBECONFIG`), never Omni network access itself, and no longer joins Tailscale for anything.

- **On PR**: runs `./hsctl run omni-sync --dry-run -e remote --git-ref <this-PR's-branch> --arg clusters=<changed> --arg machineclasses=<changed>` and posts the result as PR comments, split back into today's per-cluster/per-machineclass comments by parsing markers the script prints around each item's output. `--git-ref` is what makes this correct — without it, a dispatched run would clone and plan against `main`'s current content, not the PR's actual changes.
- **On merge to `main`**: builds a `core` kubectl context from `CORE_KUBECONFIG` and runs `./hsctl run omni-sync-and-bootstrap -e remote` — the actual sync and bootstrap happen on automatron (see below), with both steps' logs streamed into this job's log in turn

Shared Talos patches from `infra/omni/patches/` are applied alongside each cluster template.

Ansible cluster bootstrap (`bootstrap-core.yml`/`bootstrap-cluster.yml`) no longer runs here at all — see [Automatron](#automatron--kro-backed-job-runner) below.

---

## Automatron — kro-backed job runner

`apps/automatron` is a Kubernetes-native runner deployed to `core` that replaced the old GitHub Actions `ansible` job and the state-changing half of the `omni` job. What it runs — a playbook from `infra/ansible/playbooks/`, or an arbitrary script — is defined by four CRDs rather than hand-written CronJobs, backed by [kro](https://kro.run) (`apps/kro`):

- **`JobTemplate`** — one playbook or script, optionally scheduled (kro creates a `CronJob` when it is).
- **`JobRun`** — a one-off instance of a `JobTemplate`; the only path a one-off `Job` is ever created through, whether committed, triggered ad hoc via `hsctl`, or created as one step of a workflow run.
- **`JobWorkflow`** — the committable template for an ordered list of `JobTemplate` steps (each with optional per-step `args`/`dryRun` overrides — `args` is a free-form key-value map, not just a cluster target), optionally scheduled.
- **`JobWorkflowRun`** — one execution of a workflow, tracking every step's progress (status, which `Job`, current phase) in a single object instead of scattered `JobRun`s.

A workflow walks one step at a time — automatron creates each next `JobRun` itself on success — rather than kro managing the whole sequence up front (kro's dependency graph can't express "wait for a Job to finish, then create another resource" across a variable-length list).

Instances live under `infra/automatron/` (`job-templates/`, `job-workflows/`, `job-runs/`, `scripts/`), synced by their own standalone ArgoCD Application (independent of the rest of `core`'s bootstrap, so a not-yet-registered CRD can't block anything else's sync) — no Helm chart to edit to add a new job. The default set migrated from the old setup: `omni-sync`, `bootstrap-cluster`, `bootstrap-core` templates (none scheduled on their own), plus an `omni-sync-and-bootstrap` workflow (runs the first two, every 15 minutes).

Each run: a `git-key-prep` initContainer (root, to read the mounted deploy key) preps it for a non-root `git-clone` to check out `main`, then the `automatron` container (also non-root) runs the playbook or script. No Tailscale anywhere — Omni lives in the same `core` cluster, so automatron reaches it entirely in-cluster via `hostAliases` pointing the usual `REDACTED` hostnames at Omni's real ClusterIPs.

All of automatron's own credentials (Infisical login, git deploy key, and Omni access, all reused from existing identities rather than newly minted — see CLAUDE.md for the full breakdown) live under Infisical folder `/k8s/automatron`.

Ad hoc runs: `hsctl run <name> [--chain <name>[,...]] -e remote [--dry-run] [--arg key=value]... [--cluster <name>]` applies a `JobRun` (for a `JobTemplate`) or a `JobWorkflowRun` (for a `JobWorkflow`, or an ad hoc `--chain`) and streams every step's logs in turn — see `hsctl run` and "Automatron job CRDs" in [Operations → hsctl](../operations/hsctl.md).

Every `Job`/`JobRun`/`JobWorkflowRun` is named after the `JobTemplate` it's actually running and labeled `REDACTED/job-owner` (the triggering identity, `ci`, or `schedule`); finished `Job`s self-delete after a TTL, and `JobRun`/`JobWorkflowRun` CRs (run history), plus any ad hoc `JobWorkflow` from `--chain`, are pruned after 14 days by a built-in `CronJob` — a committed `JobWorkflow` is untouched. Your own identity is your OIDC email's local part (read from the `core` kubectl context already on disk, no Infisical needed), never your local username — there's no `whoami` fallback, `hsctl run` fails outright if it can't determine who you are. A Kyverno `ValidatingPolicy` (`apps/kyverno`) checks `jobOwner` at admission time so it can't be spoofed — see CLAUDE.md.

---

ArgoCD picks up any Git changes and reconciles cluster state automatically — no deploy step is needed for app-only changes.
