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
3. Boot the machine from it — Talos boots into maintenance mode and needs outbound access to Omni (REDACTED:443).
4. It appears in Omni's **Machines** list shortly after boot, identified by its Talos/SMBIOS UUID, in an unallocated state.
5. Add that UUID to the relevant `machines:` list in `clusters/<cluster>/cluster.yaml` and merge — CI's Omni template sync claims the machine and installs the cluster onto it.

Full walkthrough: `docs/operations/registering-machines.md`.

### Infrastructure (`infra/`)

- `infra/terraform/` — Terraform for cloud resources (Cloudflare DNS, DigitalOcean, Infisical project setup, Tailscale ACL/tags, core cluster bootstrap). State is in Terraform Cloud (`homescale` org, `homescale` workspace).
- `infra/automatron/ansible/` — Bootstrapping playbooks (e.g., Omni bootstrap)
- `infra/omni/patches/` — shared Talos machine config patches applied to clusters during Omni template sync

### Secrets

Infisical is the secrets store. The Infisical k8s operator (deployed as an ArgoCD app with syncWave -35) syncs secrets from Infisical into cluster namespaces. No secrets belong in this repo — the `detect-secrets` pre-commit hook will catch them. The `# pragma: allowlist secret` comment suppresses false positives on non-secret strings like secret names.

### CI/CD Pipelines

Three reusable workflows called from `ci.yaml`:
- **scan** — pre-commit, PR title lint (Conventional Commits), CodeQL, Trivy config scan
- **build** — builds only changed apps on PRs and on pushes to main (all apps on a published release), builds Docker images, runs Trivy image scan; Helm charts are linted but not published
- **deploy** — Terraform plan (PR) / apply (main), then Omni plan (PR) / sync (main) for changed clusters — both jobs dispatch every plan/apply/sync to automatron rather than running `terraform`/`omnictl` on the runner itself now; each only ever needs `core` cluster access (`CORE_KUBECONFIG`), no direct Cloudflare/Vultr/Infisical/Omni network access of its own (automatron already has that sorted, in-cluster). **No Tailscale anywhere in CI at all anymore** — the `omni` job was the last user of it (an ephemeral `tailscale/github-action` node, for reaching Omni directly to run `omnictl`) and dropped it once both the plan and sync paths moved to automatron; `terraform` never needed mesh access either, since everything it talks to (now, only from inside automatron) is a public API. Ansible cluster bootstrap no longer runs here at all — see [Automatron](#automatron-ansible-cluster-bootstrap--omni-sync)

### Networking

Tailscale is the zero-trust mesh used for human and machine access to services — CI reaching internal infra (when it needs to), and service exposure to end users.
No CI job currently needs Tailscale — the `omni` job was the last one (it used to join the tailnet as an ephemeral node, `tailscale/github-action` tagged `tag:github-actions`, to reach Omni directly for its PR-time plan) and dropped it once that moved to automatron (see [Automatron](#automatron-ansible-cluster-bootstrap--omni-sync)); Terraform never needed mesh access, since it only calls public APIs. `tag:github-actions` is still a valid `sources` identifier any app's own `tailscale:` policy block can grant access to (see below) — currently no app does, but the ephemeral-node pattern itself needs no extra setup for a future job that does.

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

`apps/automatron` (syncWave 0, `core` only) is the in-cluster runner for `infra/automatron/ansible/playbooks/` (and, for `script`-runner templates, arbitrary bash/python under `infra/automatron/scripts/`). It replaced two GitHub Actions jobs (`ansible`, and the state-changing half of `omni`) — that work now runs inside the cluster it's bootstrapping instead of on billed GH-hosted runners.

- What used to be hand-written Helm `CronJob` templates (`templates/_pod.tpl`'s `include`/`dict` boilerplate) is now a plain CRD interface, backed by [kro](https://kro.run) (`apps/kro`, syncWave -25, `core` only — installs the kro controller + its `ResourceGraphDefinition` CRD). Four `ResourceGraphDefinition`s in `apps/automatron/templates/` (`rgd-jobtemplate.yaml`, `rgd-jobrun.yaml`, `rgd-jobworkflow.yaml`, `rgd-jobworkflowrun.yaml`) define the actual `REDACTED/v1alpha1` CRDs — all cluster-scoped (single automatron install per cluster, no per-namespace isolation needed) and carry `additionalPrinterColumns` so `kubectl get jobtemplate`/`jobrun`/`jobworkflow`/`jobworkflowrun` show useful state instead of the generic Age-only default. Native objects kro creates underneath (`Job`, `CronJob`) are deliberately kept out of these CRDs' own status/printer columns wherever possible — what a person actually wants when checking a run is the `Pod` (to `kubectl logs`/`describe` it), not an intermediate object's name, so `JobRun.status.podName` (a selector-based `externalRef` collection onto the Job's own Pod, matched on the `batch.kubernetes.io/job-name` label the Job controller sets automatically — confirmed against kro's own source that `externalRef` works for native/built-in kinds via a generic dynamic client, not just CRDs) is what's surfaced as the `Pod` printer column and in `JobWorkflowRun.status.steps[].podName`, not a `Job` name. `JobRun.status.jobName` still exists in the schema (kept internal, not a printer column) since `hsctl`'s own log-streaming needs the Job name to poll `succeeded`/`failed` counts, which only exist at Job level. `JobTemplate`/`JobWorkflow` dropped their `cronJobName` status field/column entirely — a definition has no single current Pod to point at, so there's nothing useful to abstract *to*.
  - **`JobTemplate`** — one playbook (`spec.playbook`) or script (`spec.scriptPath`/`spec.scriptInterpreter` — kept as `scriptPath`, not renamed to `script` to match `playbook`, despite the inconsistency: kro refuses to reconcile a CRD field rename in place, treating it as a breaking schema change, and the fallout from trying it once already (see the `terraform`/CI-identity bullet below) cascaded into `JobRun`'s own RGD going `Inactive` — its CEL template references `template.spec.<field>` against this CRD's actual live schema, so a rename here breaks ad hoc runs of *every* template, not just this one), optionally `spec.schedule`d (kro creates a `CronJob` when set — `includeWhen` on the schedule field, no `suspend: true` trick needed). Omitting `schedule` makes it template-only, runnable only via a `JobRun`. `spec.locking` (default `false`, added after the CRD already existed — purely additive, not a rename, so no breaking-change issue) gates a generic Lease-based mutex — see the Locking bullet below.
  - **`JobRun`** — a one-off instance of a `JobTemplate`. This is the *only* place a one-off `Job` ever gets created from a template: a human commits one under `infra/automatron/job-runs/`, `hsctl run <template> -e remote` creates one ad hoc, or it's one step of a `JobWorkflowRun` (below). It resolves its `JobTemplate` via a kro `externalRef` whose lookup name is a CEL expression over the `JobRun`'s own `spec.templateRef` (not a static name) — if this dynamic lookup ever stops resolving, the fallback is having `JobRun` carry its own `playbook`/`scriptPath` fields directly instead of inheriting them. `status.phase` (`Pending`/`Running`/`Succeeded`/`Failed`) is projected from the underlying `Job`'s own status via CEL. `spec.gitRef` (default `"main"`) overrides the `git-clone` initContainer's checked-out ref — the only real use is `deploy.yaml`'s PR-time plan, which needs to see the PR's own branch content rather than `main`'s (see `hsctl run --git-ref` below); every other caller leaves it at the default, and `entrypoint.sh`'s chain continuation propagates whatever value the run started with (`GIT_REF` env var, same mechanism as `JOB_OWNER`) to every subsequent step.
  - **`JobWorkflow`** — the committable *template* for an ordered sequence of steps, each `{templateRef, args, dryRun}` (`args`/`dryRun` optional per-step overrides — see below). Like `JobTemplate`, optionally `spec.schedule`d.
  - **`JobWorkflowRun`** — one *execution* of a workflow, tracking every step's progress in a central place instead of making callers hunt scattered `JobRun`s by label. `spec.steps` is always the *fully resolved* step list for that run (concrete values, not a reference) — resolution happens once, at creation time, by whoever creates it (see precedence rule below); `spec.workflowRef` always points at a real `JobWorkflow` — standardized, no empty-ref case — `hsctl run <template> --chain ...` creates a throwaway ad hoc `JobWorkflow` first (same name as the run itself; different kinds, no collision; labeled `REDACTED/adhoc: "true"` so the cleanup `CronJob` below knows to eventually prune it, unlike a committed one) rather than leaving it unset. Purely a status-aggregation view otherwise — no resources of its own beyond a label-selector `externalRef` collection over child `JobRun`s (not the underlying `Job`s directly — every step, including step 0 of a scheduled run, always goes through a `JobRun` now, so aggregating over `JobRun` gives richer status — `templateRef`, `stepIndex`, `phase` — for free), projected via CEL `.map()`/`.exists()`/`.all()`.
  - `JobTemplate`/`JobRun`/`JobWorkflow` steps all take `args`, a free-form `map[string]string` of extra-vars/script arguments — not `cluster` as a dedicated field, since `cluster` was the only one in use early on and more will follow (any key the playbook/script itself expects works; `entrypoint.sh` passes the whole map to Ansible as extra-vars, and exports it as `ARGS_JSON` for scripts to parse themselves). `cluster` survives only as a CLI convenience on `hsctl run` (`--cluster X` is sugar for `--arg cluster=X`) and as one special-cased key `entrypoint.sh` also forwards to Ansible's own `target` variable for `bootstrap-cluster`/generic playbooks (unrelated to automatron — that's just what those playbooks have always called it). Precedence for a workflow's steps (applies both to a scheduled `JobWorkflow` firing and to `hsctl run <workflow-or-template> [--chain ...] --arg key=value`/`--cluster X`), per key: a step's own explicit `args` entry always wins; else, for an ad hoc `hsctl` run only, the CLI-supplied value; else the step's `JobTemplate`'s own `defaultArgs`. Only the first two tiers are resolved by whoever builds `JobWorkflowRun.spec.steps` (`hsctl`, in bash/jq — see `hsctl.d/run.sh`'s `_run_resolve_workflow_steps`, a plain jq object merge, `$cli + step_args`) — the third tier is left to `JobRun`'s own existing CEL fallback, using kro's `map.merge()` CEL library function (`template.spec.?defaultArgs.orValue({}).merge(schema.spec.?args.orValue({}))`, confirmed available in the deployed kro version by reading its source — "keys from the second map overwrite the first"), so nothing needs to know a `JobTemplate`'s defaults ahead of time. `dryRun` has no empty-ish sentinel to detect "unset" the way an args key's absence does, so it's resolved as OR instead (true from either side wins).
  - Chaining is fully bash-driven, not kro-managed — kro's `forEach`/collections can't express "step N waits for step N-1" (collection items are independent). `apps/automatron/entrypoint.sh` reads `WORKFLOW_RUN_NAME`/`STEP_INDEX` (set only when this run is a workflow step) and, on success, reads `JobWorkflowRun.spec.steps[STEP_INDEX+1]` (already resolved — no further precedence logic needed) and creates a `JobRun` for it if present, labeled `REDACTED/workflow-run` so it's found by the next lookup and by `JobWorkflowRun`'s own status aggregation. A scheduled `JobWorkflow`'s `CronJob` runs a lightweight "kickoff" container (built with `jq -n`, not heredocs — a heredoc's closing delimiter needs column-0 alignment, which a script embedded in a YAML block scalar inside a Helm template can't reliably guarantee; also **no `${VAR}`-braced bash expansion anywhere in it** — kro's CEL substitution scans the whole template text and misparses `${...}` as a CEL expression regardless of context, confirmed live once already) that creates the `JobWorkflowRun` (with every step already resolved, verbatim from `JobWorkflow.spec.steps` — no CLI overrides to apply for a scheduled firing) plus step 0's `JobRun`, then exits — a native `CronJob` can only ever template a plain `Job`, never a CR directly. Migrated default: `job-workflows/omni-sync-and-bootstrap.yaml` (`schedule: "*/15 * * * *"`, steps `[omni-sync, bootstrap-cluster]`) — clusters always exist in Omni before bootstrap-cluster runs against them.
  - The pod boilerplate (serviceAccount, volumes, `git-key-prep`/`git-clone`/`omni-hosts` initContainers, base container) is duplicated across the RGDs (in full for `JobTemplate`/`JobRun`/`JobWorkflow`'s kickoff container; `JobWorkflowRun` has none) — kro has no Helm-`include`-equivalent for sharing a template fragment across `ResourceGraphDefinition`s. Keep them in sync by hand when changing shared pod shape.
  - Every `Job` kro creates is named after the `JobTemplate` actually being executed, not a bare step number — a chained hop's `JobRun` is `<run>-step<N>-<templateRef>`, e.g. `max-omni-sync-1234567890-step1-bootstrap-cluster` — since the step number alone doesn't tell you what's actually running, which was confusing enough in practice to fix. `JobRun`/`JobWorkflowRun`/`JobWorkflow` CR names (both committed and ad hoc/dynamically-created ones) are deliberately left with no `atm-`/`automatron-` prefix — `kubectl get jobrun`/etc. already makes plain what kind of object you're looking at. Every root run name (ad hoc, CI, or scheduled — see `job-owner` below) has its owner/template-or-workflow-name components truncated to 16 chars each (`hsctl.d/run.sh`'s `_run_truncate` / the kickoff container's `truncate16`) — this name is reused as a `REDACTED/workflow[-run]` label **value**, not just an object name, and Kubernetes caps label values at 63 bytes; confirmed live, an untruncated name (`job_owner=ci` plus a longer workflow name) broke both kro's own label-selector reconciliation (`ResourcesReady: invalid label selector ... must be no more than 63 bytes`) and hsctl's own `kubectl create` calls outright, failing the whole CI sync. A chained step's own composed name (`<run>-step<N>-<templateRef>`) is *also* truncated as a whole, separately from `run_name`'s own components, and capped at **59** bytes, not 63 — `entrypoint.sh`'s chain continuation, the kickoff container's step 0, and `hsctl run --chain`'s own step 0 all cap the fully-composed CR name there (stripping a trailing hyphen the cut can leave dangling) rather than assuming `run_name` being short leaves enough room, since `templateRef` itself is unbounded — confirmed live, a stale pre-truncation `JobWorkflowRun` whose own name exceeded 63 bytes could never be reconciled (kro requeues it with backoff forever, since the name is immutable) and had to be deleted by hand. The 59 (not 63) is deliberate headroom: unlike a CR, the native `Job`/`Pod` kro creates from a `JobRun` *does* carry an `atm-` prefix over the `JobRun`'s own name (`rgd-jobrun.yaml`'s `job` resource — same reasoning as `rgd-jobtemplate.yaml`'s scheduled `CronJob`, above) — a `Job`/`Pod` sits in a flat namespace among unrelated objects and so is what actually needs the at-a-glance marker, and that extra 4 bytes has to fit in the same 63-byte cap. `entrypoint.sh`'s active-Job dedup guard checks for a `Job` named `atm-$run_name`, not `$run_name` itself, for the same reason. Both `rgd-jobrun.yaml`'s `job` resource and `rgd-jobtemplate.yaml`'s `cronJob` resource set `REDACTED/template`/`job-owner` labels at **both** the `Job`'s own `metadata.labels` and its pod template's `metadata.labels` — label queries against `kubectl get jobs` only see Job-level labels, not pod-template-level ones, so a label meant to be queryable via `kubectl get jobs -l ...` (as `entrypoint.sh`'s active-Job dedup guard does) has to actually be set there, not just on the pod template (a real bug in an earlier version of `rgd-jobtemplate.yaml` — the label was pod-template-only, so that query would've silently found nothing for scheduled runs).
  - `REDACTED/job-owner` labels every `JobRun`/`JobWorkflowRun`/`Job`: the identity `hsctl run` ran as for an ad hoc run, `ci` for `deploy.yaml`'s CI-triggered sync, or `schedule` for a cron-triggered one — set once at the start of a chain and threaded through unchanged to every subsequent hop (`JOB_OWNER` env var, same propagation mechanism as `WORKFLOW_RUN_NAME`/`STEP_INDEX`). Every root run name embeds it (`<owner-or-"schedule">-<name>-<timestamp>`, both middle components truncated to 16 chars — see above; the `Job`/`Pod` created from it is this same name with `atm-` prepended, not embedded in the CR name itself). `hsctl.d/run.sh`'s `_run_job_owner` resolves your own identity, in order: `$HSCTL_JOB_OWNER` if set (`deploy.yaml` sets it to `ci`); else `hsctl_oidc_username` (`hsctl.d/_lib.sh`) — the local part of the OIDC `email` claim (e.g. `max` for `max@REDACTED`), decoded from a kubelogin `id_token` minted with the exact issuer-url/client-id/scope args already sitting in the local `core` kubectl context's exec config (`kubectl config view`, read straight off disk — **no Infisical call**, since only a handful of people have Infisical access but ~everyone running `hsctl run` already has a working `core` context; those two values aren't secret anyway, just OIDC discovery/client identifiers), silent/non-interactive as long as a still-valid or refreshable token is already cached at `~/.kube/cache/oidc-login` (which it will be, immediately after `_run_remote`'s own preceding `kubectl ... --context core` calls warm it — `_run_remote` deliberately resolves `job_owner` *after* ensuring a `core` context exists, not before). There is deliberately **no `whoami`/local-username fallback** — local usernames routinely don't match the `@REDACTED` identity closely enough to trust for an ownership/audit label, so `_run_job_owner` hard-fails (`exit 1`, clear error message) rather than silently mislabeling a job. `hsctl_oidc_username` also never triggers an interactive `infisical login`/browser flow itself — every caller captures its stdout via command substitution (`owner=$(_run_job_owner)`), and an interactive prompt's own output would otherwise get swallowed into the job-owner string instead of shown to the user (hit exactly this live during implementation) — it just fails closed if no cached token/context is already available. Every value is sanitized the same way regardless of source (lowercase, `[a-z0-9-]` only, no leading/trailing/repeated hyphens).
  - **`jobOwner` isn't currently authenticated against the caller** — `spec.jobOwner` (and the label mirroring it) is just a field on the CR, so anyone with the `job-operator` ClusterRole (below) could hand-write a `JobRun`/`JobWorkflowRun` — or simply set `$HSCTL_JOB_OWNER` themselves — claiming to be `schedule`, `ci`, or another teammate, defeating the ownership tracking above. `require-automatron-job-owner-integrity` (`apps/kyverno/templates/policy-automatron-job-owner.yaml`) closes this at admission time: `jobOwner` must equal the `job-owner` label (catches a hand-written CR that forgets one or the other, which would otherwise silently break `entrypoint.sh`'s dedup-guard query too); only automatron's own ServiceAccount (`system:serviceaccount:automatron:automatron`, the identity chaining/kickoff/cleanup run as) may set `jobOwner: schedule`; and any caller whose authenticated `request.userInfo.username` looks like an OIDC email (i.e. an ordinary human through `job-operator`, not automatron's SA) must set `jobOwner` to their own sanitized local-part — they can't claim to be someone else, `schedule`, or `ci`. This intentionally does **not** (and structurally can't) constrain `deploy.yaml`'s CI sync step: it authenticates via `CORE_KUBECONFIG`, which is Vultr's own cluster-admin kubeconfig, not a scoped identity — a policy engine can't meaningfully box in a credential that can already rewrite or delete the policy itself. Ships with `validationActions: [Audit]` initially (violations logged as `PolicyReport`s, nothing blocked) specifically because the human-identity match assumes an email local-part needs no further sanitizing beyond lowercasing — untested against every real `@REDACTED` address — flip to `[Deny]` once a `PolicyReport` sweep confirms no false positives.
  - **Locking**: any `JobTemplate` can set `spec.locking: true` to make `entrypoint.sh` acquire a `Lease` (named `automatron-<template>-lock`; `automatron-lock` Role/RoleBinding in `apps/automatron/templates/role.yaml`/`rolebinding.yaml`, generic — any lease name in the namespace, not tied to one template) via atomic `kubectl create` before running that template's playbook/script, and release it (`trap ... EXIT`) when done — a real mutex, not a check-then-act race window. Retries with a bounded wait (1800s) if another run already holds it, and reclaims a stale lock if the Job that's holding it no longer exists. `TEMPLATE_NAME`/`LOCKING` (both RGDs resolve `template.spec.locking`/`schema.spec.locking` into these) and `JOB_NAME` (a Downward API env var reading the `batch.kubernetes.io/job-name` label the Job controller sets on every Pod) are what let it name the lock and identify itself as the holder. Lives in `entrypoint.sh` rather than per-script (originally implemented only in `terraform.sh`, then generalized once `omni-sync.sh` needed the same protection) so any future script opts in with one field instead of reimplementing it. This is what lets `deploy.yaml` skip GitHub Actions' own `concurrency:` gate entirely — every state-changing dispatch already queues in-cluster.
  - Cleanup: every RGD that creates a `Job` (`JobTemplate`'s scheduled `CronJob`, `JobRun`'s own `Job`, `JobWorkflow`'s kickoff `CronJob`) sets `ttlSecondsAfterFinished: {{ .Values.automatron.jobTtlSeconds }}` (default 1800 — 30 minutes, in `apps/automatron/app.yaml`) — Kubernetes' own TTL-after-finished controller, which deletes both the `Job` and its `Pod` this many seconds after completion, so finished `Job`s/`Pod`s don't sit around; no separate automatron-driven sweep needed for these, since it's a native, continuously-reconciling controller rather than a periodic batch job. `JobRun`/`JobWorkflowRun` CRs (run history) are pruned once they're older than 14 days by `apps/automatron/templates/cronjob-cleanup-runs.yaml` — a plain native `CronJob` (daily, `0 3 * * *`), not an automatron `JobTemplate` CR, since this is a built-in operational task rather than something users commit/run themselves, and it'd be circular for the thing pruning run history to itself need a `JobRun` wrapper. It also prunes `JobWorkflow` CRs carrying `REDACTED/adhoc: "true"` — the throwaway ones `--chain` creates (below), which exist purely to back one ad hoc run — after the same 14 days; a committed `JobWorkflow` has no such label, so the label selector alone keeps git/ArgoCD-managed ones untouched, no other distinction needed.
- **`terraform`** (`infra/automatron/job-templates/terraform.yaml`, `scriptPath: terraform.sh`, `schedule: "*/15 * * * *"`) plans/applies the single shared `infra/terraform` workspace (state stays in Terraform Cloud — not split per-cluster) from automatron instead of CI, for the same reason `omni-sync` moved: continuous reconciliation on free in-cluster compute instead of only-on-push, billed CI minutes.
  - **Auth**: `provider "infisical"` (`infra/terraform/providers.tf`) picks OIDC or `universal` auth (`var.infisical_auth_method`) at plan time — there's no GitHub OIDC token available inside a Kubernetes Job for automatron to present. Both methods authenticate as the same `ci` identity (`var.infisical_github_actions`, full project-admin, provisioned outside Terraform — it predates this and keeps its original GitHub-OIDC auth alongside a universal auth method added for automatron's dispatch); universal auth uses that identity's client ID/secret (`INFISICAL_CI_CLIENT_ID`/`_SECRET`, symlinked from Infisical's `/ci` into `/k8s/automatron`, already in automatron's pod env), not the k8s Infisical Operator's own identity — that one stays low-privileged (project `member`, narrow org `identity-reader` role — `infra/terraform/modules/infisical/identities.tf`) for its actual job of syncing secrets, since terraform's own admin-level operations (managing `infisical_identity`/`infisical_org_role` resources) can't be bootstrapped by an identity trying to grant itself permission to do so — hit exactly this live (403s reading/modifying `infisical_identity.k8s_operator`) before moving auth to `ci`. `CLOUDFLARE_API_TOKEN` and `TF_TOKEN_app_terraform_io` (both otherwise picked up implicitly from the process environment by their respective tools, not through any Terraform variable) and `INFISICAL_ORG_ID` (needed even to authenticate, so can't itself come from Infisical) are synced into `/k8s/automatron` as references to the `/ci` folder's own values (`INFISICAL_ORG_ID` is a literal copy of `var.org_id`, since it isn't stored in Infisical anywhere today) — same `automatron-secrets` `envFrom` every other RGD already has, no new plumbing.
  - **Locking**: `locking: true` (see the generic Locking bullet above) — not redundant with Terraform Cloud's own state lock, which only hard-fails a concurrent run outright rather than queueing it.
  - **Targeting**: `hsctl run terraform --cluster <name>` (`--cluster` is already sugar for `--arg cluster=X`, no new hsctl code needed) scopes the run to just that cluster's own resources. Computed from an *untargeted* `terraform plan`'s own JSON output (`terraform show -json`), not `terraform state list` — state only shows what's already been created, which would miss a brand new cluster's first-ever tunnel. Cluster-keyed resources (tunnel, tunnel config, VolSync secrets) are matched by their resource address containing `["<cluster>"]`/`["<cluster>/`; `cloudflare_dns_record`/`cloudflare_zero_trust_access_application` are keyed by FQDN instead, so those are matched via a direct scan of `apps/*/app.yaml`'s `exposePublic[].cluster` — the same filter the `.tf` itself applies, kept independent of any hardcoded resource-type list so it can't drift from the HCL.
  - **CI** (`deploy.yaml`'s `terraform` job): same `--git-ref`-for-PR-time-correctness and marker-based output pattern as `omni-sync` — `Plan via automatron` runs `hsctl run terraform --dry-run -e remote --git-ref <PR-branch>`, and the rendered Tailnet ACL (previously extracted from a local `terraform show -json` file) is now parsed from a `=== BEGIN/END ACL_JSON ===` block in the streamed output before the existing artifact-upload/topology-map steps run unchanged.
- Instances (the things you actually commit) live under `infra/automatron/`, synced by its own standalone ArgoCD Application (`clusters/core/automatron-jobs.yaml`) rather than as a source on `apps-core` — deliberately independent, so a pending `REDACTED` CRD (before kro's reconciled the RGDs) can't block `apps-core`'s own multi-source sync, which would otherwise deadlock atomically (confirmed live — see git history on `clusters/core/apps.yaml` and `clusters/core/automatron-jobs.yaml`). Subdirs: `job-templates/`, `job-workflows/`, `job-runs/` (rare — most runs are ad hoc), `scripts/`, `ansible/` (playbooks/roles — moved here from a former top-level `infra/ansible/` once automatron became the only thing that ever runs them). `.github/scripts/validate-manifests.sh` conforms this tree directly (no Helm rendering involved), scanning every `Application` manifest under `clusters/<cluster>/`, not just `apps.yaml` — `ansible/`'s own `.yml` files are plain playbooks/roles, not Kubernetes manifests, so both this script and the real `automatron-jobs` Application (`clusters/core/automatron-jobs.yaml`) carry a `directory.exclude: 'ansible/**'` to skip them; the script's own exclude matching is a path glob against the source-relative path (same semantics as ArgoCD's), not a plain filename match, specifically so a whole-subtree pattern like this works. See `docs/operations/hsctl.md`'s "Automatron job CRDs" section for the field reference and examples.
- Each run's pod: `git-key-prep` initContainer (root, on automatron's own image running `git-key-prep.sh` — see below) → `git-clone` (`git-sync` image in one-time mode, checks out `main` via SSH) → `automatron` container (ansible-core/kubectl/helm/omnictl/envsubst baked into the image, running as a non-root user; ansible collections installed at start from the git-cloned `requirements.yml`). `entrypoint.sh` picks `ansible-playbook` vs. the raw script based on which of `PLAYBOOK`/`SCRIPT_PATH` is set (exactly one must be).
- **No Tailscale anywhere in this app** — Omni lives in the same cluster (`core`), so automatron reaches it entirely in-cluster. Each RGD's pod template sets `hostAliases` pointing `REDACTED`/`REDACTED` at the real ClusterIPs of `apps/omni`'s `api`/`k8s` Services (resolved at pod start by the `omni-hosts` initContainer, not via Helm's `lookup`, which ArgoCD's renders have been observed returning empty for), so `OMNI_ENDPOINT` and the rest of the ansible/omnictl config need no changes at all — same hostnames, same real cert, just resolved differently. `omni_k8s_grant` in `acl.tf` is `sg-k8s-admin`-only (break-glass) since nothing else needs Tailscale access to Omni's k8s-proxy.
- Automatron's own credentials are mostly *reused*, not re-provisioned, since identities/service accounts are billed or administratively heavier than plain secrets: its Infisical login reuses the k8s Infisical Operator's own identity (`INFISICAL_OPERATOR_CLIENT_ID`/`_SECRET` at `/k8s/infisical`, synced via the `automatron-infisical-operator-creds` CR), and `GIT_DEPLOY_KEY` in `/k8s/automatron` is an Infisical secret *reference* pointing at the same value as `/k8s/argocd/deploy-key`'s `sshPrivateKey`, not a separately-minted key. Its Omni access (`OMNI_SERVICE_ACCOUNT_KEY`) lives directly in `/k8s/automatron` alongside those, synced by the same `automatron-secrets` CR as everything else there — no dedicated CR, and no longer tied to the `omni` CI job's `/github-actions` credential the way it originally was. `git-key-prep` (`apps/automatron/git-key-prep.sh`, baked into the automatron image) runs as root because secret-mounted files come out root-owned at mode `0600` (required — sshd's strict key-perm check rejects any group/other bits); it copies the key into a writable volume (restoring a trailing newline the stored value is missing, which OpenSSH's parser needs) and hands ownership to `git-clone`'s actual non-root UID, so `git-clone` itself doesn't need root.
- `bootstrap-core`/`cluster-secrets` still separately read `/k8s/argocd/deploy-key` and `/k8s/infisical` at runtime — that's automatron *propagating* ArgoCD's/the k8s-operator's own credentials into whatever cluster it's bootstrapping, unrelated to the reuse above.
- `CORE_KUBECONFIG` (core is Vultr VKE, reached over the public internet — no Tailscale needed for `bootstrap-core`, or for the `deploy.yaml` Sync step below) is Terraform-managed, under `/k8s/automatron`.
- Ad hoc / on-demand runs: `hsctl run <name> [--chain <name>[,...]] -e remote [--dry-run] [--arg key=value]... [--cluster <name>]` (see `docs/operations/hsctl.md`) applies a `JobRun` (for a `JobTemplate`) or a `JobWorkflowRun` + step-0 `JobRun` (for a `JobWorkflow`, or an ad hoc `--chain`, which creates a throwaway `JobWorkflow` first — see above), then streams every step's logs in turn as `entrypoint.sh` creates them. `team-infra-plat`/`team-sec-plat` can do this without PIM (`job-operator` ClusterRole in `apps/rbac`, with `create`/`delete`/`get`/`list` on `REDACTED` `jobruns`/`jobworkflowruns`, `get`/`list` on `jobtemplates`, and `create`/`get`/`list` on `jobworkflows` — `create` for `--chain`'s ad hoc `JobWorkflow`, `jobtemplates` stays git-only since there's no ad hoc equivalent for those — also bound to automatron's own ServiceAccount for its self-chaining and kickoff container); log reading already worked via the existing `pod-operator` binding.
- `deploy.yaml`'s `omni` job: both the PR-time **Plan** and the merge-to-`main` **Sync** step build a `core` kubectl context from `CORE_KUBECONFIG` and dispatch to automatron, so this job never touches Omni's network directly and needs no Tailscale/omnictl/yq of its own — just `kubectl` + `hsctl`. **Plan** runs `./hsctl run omni-sync --dry-run -e remote --git-ref "$(github.head_ref)" --arg clusters=<csv> --arg machineclasses=<csv>` (an empty `--arg` value means "none of this kind" — distinct from omitting the key, which `omni-sync.sh` treats as "everything"; `--git-ref` is the PR's own branch, so the plan reflects that PR's actual changes, not `main`'s current content — see `JobRun.spec.gitRef` above), then the *"Post plan results as PR comments"* step splits the one streamed log back into today's separate per-cluster/per-machineclass comments by parsing `omni-sync.sh`'s own `=== BEGIN/END <KIND> <name> ===` markers. **Sync** runs `./hsctl run omni-sync-and-bootstrap -e remote` (unchanged), so the actual state-changing sync *and* the bootstrap-cluster run after it happen on automatron with both steps' logs streamed straight into the GitHub Actions log in turn.

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
