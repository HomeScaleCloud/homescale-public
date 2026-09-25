# hsctl

`hsctl` is a small bash CLI for day-to-day operator tasks against the HomeScale fleet: listing clusters and machines, fetching kubeconfigs, browsing restic snapshots, power-cycling machines, jumping into ArgoCD, and managing Entra PIM assignments.

Most commands talk to Omni and each cluster's API server over Tailscale, so they need an active Tailscale connection. The exception is `hsctl pim` and the `pim*` resources under `hsctl get`, which talk to Microsoft Graph/ARM directly and don't need Tailscale.

Source: `hsctl` (entrypoint) and `hsctl.d/*.sh` (one file per top-level command) at the repo root.

## Installing / updating

```bash
hsctl --update
```

Fetches the latest `hsctl` and `hsctl.d/*.sh` from the `main` branch of this repo via `gh api` and installs them to `~/.local/bin`. Run this after `hsctl` itself changes.

Also installs any missing dependencies listed in `hsctl.d/requirements.txt` (one Homebrew package per line) — fails with a link to https://brew.sh if `brew` isn't on `PATH`.

## `hsctl get`

```
hsctl get <resource> [-o table|yaml|json] [flags...]
```

Output format defaults to `table`; pass `-o yaml` or `-o json` for scripting.

| Resource | Usage | Description |
|----------|-------|-------------|
| `clusters` | `hsctl get clusters` | List Kubernetes clusters reachable via Tailscale |
| `kubeconfig` | `hsctl get kubeconfig <cluster> [--omni\|--break-glass]` | Write a kubeconfig context for `<cluster>`. Default: [direct to the real apiserver](../architecture/networking.md#direct-cluster-api-access) via OIDC login (needs the `kubectl-oidc_login` [krew](https://krew.sigs.k8s.io/) plugin; issuer/client ID come from Infisical at `/k8s/oidc`). `--omni` runs `omnictl kubeconfig --cluster <cluster>`. `--break-glass` runs `omnictl kubeconfig --break-glass --cluster <cluster>` to bypass Omni and reach nodes directly |
| `machines` | `hsctl get machines [--cluster <name>]` | List all Omni machines with power state, enriched with node name, cluster, and role for machines already assigned to a cluster. Filter to one cluster with `--cluster`/`-c` |
| `machine` | `hsctl get machine <id\|node-name>` | Show details for a single machine, by Omni machine ID or Kubernetes node name |
| `snapshot` | `hsctl get snapshot <app>` | List restic snapshots for an app's VolSync-backed PVC, with timestamps and IDs — see [Backups: restore procedure](../architecture/backups.md#restore-procedure) |
| `pimrole` | `hsctl get pimrole` | List your eligible + active Entra directory role PIM assignments (Graph API) |
| `pimgroup` | `hsctl get pimgroup` | List your eligible + active PIM-for-Groups assignments (Graph API) |
| `pimazurerole` | `hsctl get pimazurerole --scope <arm-scope>` | List your eligible + active Azure resource RBAC PIM assignments (ARM API) |
| `pimapproval` | `hsctl get pimapproval [role\|group\|azure] [--scope <arm-scope>]` | List pending PIM approval requests: ones you can approve and your own, tagged `approver`/`requestor`, with the requester's display name and email (`role`/`group` only — Graph API). No type given: shows both `role` and `group` |

## `hsctl argocd`

```bash
hsctl argocd login <cluster>   # argocd CLI login via SSO to that cluster's ArgoCD
hsctl argocd open <cluster>    # open that cluster's ArgoCD UI in the browser
```

Both resolve to `argocd.<cluster>REDACTED` — the [Tailscale internal service address](../architecture/networking.md#internal-service-exposure) for ArgoCD on that cluster.

## `hsctl machine`

```
hsctl machine power on|off|reset [--force] <id|node-name> [<id|node-name>...]
hsctl machine bmcreset <id|node-name>
```

Takes action directly against a physical machine — unlike `hsctl get`, this changes real hardware state. Accepts an Omni machine ID or a Kubernetes node name (resolved the same way as `hsctl get machine`).

`power` accepts multiple space-separated targets and acts on each in turn. It continues past a single machine's failure (unresolved name, credential fetch, or ipmitool/talosctl error) but exits non-zero if any target failed.

| Action | Mechanism | Effect |
|--------|-----------|--------|
| `on` | `ipmitool chassis power on` | Power on |
| `off` | `talosctl shutdown` | Graceful OS shutdown (cordon/drain, then power off) |
| `off --force` | `ipmitool chassis power off` | Immediate hard power off, bypassing Talos |
| `reset` | `ipmitool chassis power reset` | Warm reset (equivalent to the physical reset button) |
| `bmcreset` | `ipmitool mc reset cold` | Cold-restart the BMC itself — **host power is left untouched**; the controller takes ~1–2 min to come back |

`off` requires [`talosctl`](https://www.talos.dev/latest/introduction/getting-started/#talosctl) (`brew install talosctl`). If a graceful shutdown isn't possible or desired, pass `--force` to hard-cut power via IPMI instead.

`on`, `reset`, `off --force` and `bmcreset` go over the BMC via IPMI ([`ipmitool`](https://github.com/ipmitool/ipmitool), `brew install ipmitool`). IPMI is used instead of Redfish because this fleet's Supermicro BMCs gate every Redfish endpoint behind a paid `SUM DCMS OOB` license — IPMI-over-LAN works unlicensed with the same credentials.

Each `ipmitool` call prefers RMCP+ (`-I lanplus`) but falls back to legacy IPMI 1.5 (`-I lan`) when the RMCP+ session can't be established, so `hsctl machine` keeps working even when a BMC's RMCP+ stack is broken. `bmcreset` itself is almost always carried by the 1.5 fallback, since the usual reason to run it is that `lanplus` is down.

### `Error in open session response message : invalid role`

Seen on the X11SSH-F BMCs: every `-I lanplus` session fails with `invalid role` / `Unable to establish IPMI v2 / RMCP+ session` (RMCP+ status `0x09`), while `-I lan` (IPMI 1.5) keeps working normally.

**Cause:** the BMC's cipher-suite privilege table is corrupt — no *usable* RMCP+ cipher suite has a privilege level assigned, so the BMC can't grant any role and rejects the Open Session Request outright.

```bash
ipmitool -I lan -H <bmc-ip> -U <user> -P <pass> lan print 1 | grep -A1 'Cipher Suite'
#   RMCP+ Cipher Suites   : 3,17          <- the only suites this BMC offers
#   Cipher Suite Priv Max : aXXXXXXXXXXXXXX   <- only suite 0 has a priv; suites 3 & 17 are "unused"
```

`hsctl machine bmcreset` does **not** fix this (it survives a cold reset — it's persisted NVRAM config, not a transient hang), and this firmware **rejects rewriting the table over IPMI** — both `ipmitool ... lan set 1 cipher_privs ...` (`LAN Parameter Data does not match!`) and a raw `Set LAN Config Parameters` for parameter 24 (`rsp=0xcc: Invalid data field in request`).

**Remediation, in order:**

1. **Do nothing to the BMC** — `hsctl machine`'s `-I lan` fallback already carries every power/reset action. Only pursue a fix if you need `lanplus` specifically (e.g. an external tool that can't do 1.5).
2. **BMC web UI** (`https://<bmc-ip>/`, reachable even in this state) → if it exposes cipher-suite privileges, set suite 3 (and 17) to Administrator there; otherwise **Maintenance → Factory Default** rebuilds the config. A factory reset wipes the `ADMIN` password (back to `ADMIN`/`ADMIN`), the `talos-agent` user, and any static LAN settings — re-set the password afterward and update Infisical at `/bmc/<machine-id>`.
3. **Reflash the BMC firmware** (reload/upgrade from 1.78) to rebuild NVRAM.

If one X11SSH-F BMC is in this state, check the others: `ipmitool -I lanplus -H <bmc> -U … -P … mc info` succeeding is the all-clear.

BMC connection info (`IP`, `VENDOR_USERNAME`, `VENDOR_PASSWORD`) is fetched at runtime from Infisical at `/bmc/<machine-id>` — populate this path per-machine before an IPMI-backed `hsctl machine power` action will work for it. Progress and outcome are reported via timestamped `INFO`/`ACTION`/`OK`/`ERROR` log lines.

## `hsctl run`

```
hsctl run <name> [--cluster <name>] [--arg key=value]... [-e|--execution-mode local|remote] [--dry-run] [--chain <name>[,<name>...]]
```

Runs a playbook or script via [automatron](../architecture/overview.md#automatron--kro-backed-job-runner) (the in-cluster runner on `core`), or locally. `<name>` is required (no "run everything" shortcut).

In `-e remote` mode (the default), `<name>` is the name of an `AutomatronJobTemplate` or `AutomatronJobWorkflow` custom resource — CRDs [kro](https://kro.run) generates from the `ResourceGraphDefinition`s shipped in `apps/automatron/templates/`; the actual instances live under `infra/automatron/job-templates/` and `infra/automatron/job-workflows/`. `hsctl` checks for a matching `JobTemplate` first, then a `JobWorkflow`:

| Kind | Effect |
|------|--------|
| `JobTemplate` | Runs it directly — one `JobRun` CR, one `Job`. `--arg`/`--cluster`/`--dry-run` override the template's own `spec.defaultArgs`/nothing (templates don't have a stored dry-run default) |
| `JobWorkflow` | Resolves every step's `args`/`dryRun` (a step's own entry for a given key always wins; `--arg`/`--cluster`/`--dry-run` apply to any step that doesn't already set that key; a key set by neither falls through to its own `JobTemplate`'s `defaultArgs`), creates a `JobWorkflowRun` with the resolved steps plus a `JobRun` for step 0, then streams every subsequent step's logs in turn as `entrypoint.sh` creates them |

Three `JobTemplate`s ship pre-migrated from the old Ansible-only setup (`infra/automatron/job-templates/{omni-sync,bootstrap-cluster,bootstrap-core}.yaml`), none scheduled on their own — `bootstrap-cluster` takes `--cluster <name>` (its Omni cluster ID, e.g. `boa1-prod`); `bootstrap-core` ignores it. The `omni-sync-and-bootstrap` `JobWorkflow` (`infra/automatron/job-workflows/`) runs both every 15 minutes and is also the target for an ad hoc "sync and bootstrap everything" run.

`-e`/`--execution-mode` is `local` or `remote` (default `remote`):

- **`remote`** applies a `JobRun`/`JobWorkflowRun` CR on automatron in the `core` cluster, waits for kro to materialize the underlying `Job`(s), and streams logs immediately. Requires a Tailscale-reachable `core` apiserver (same as `hsctl switch`/`hsctl get kubeconfig`) and `team-infra-plat`/`team-sec-plat` membership — no PIM needed. If a `core` kubectl context already exists (e.g. CI pre-seeds one from `CORE_KUBECONFIG`), it's reused as-is instead of triggering an interactive OIDC login.
- **`local`** treats `<name>` as an Ansible playbook filename (minus `.yml`) under `infra/ansible/playbooks/` — no `JobTemplate`/`JobWorkflow` lookup, since kro/automatron aren't involved. Only understands `--cluster`, not `--arg` (there's no CRD/args-map machinery to resolve locally). Clones `HomeScaleCloud/homescale@main` fresh into a temp directory (`gh repo clone`, requires `gh auth login`) and runs `ansible-playbook` against that checkout, cleaning it up afterward — never against whatever's checked out locally, which could be a branch, stale, or have uncommitted changes. Still needed for the very first core bootstrap, before automatron exists, or for disaster recovery if automatron itself is down.

`--arg key=value` (repeatable) sets an arbitrary extra-var/script argument — nothing automatron-specific, any key the playbook or script itself expects works; `entrypoint.sh` passes the whole resolved set to Ansible as extra-vars wholesale, and exports it as `ARGS_JSON` for scripts to parse themselves. `--cluster <name>` is sugar for `--arg cluster=<name>` — the one arg key common enough to deserve its own flag.

`--dry-run` is only meaningful for playbooks that act on it — currently just `omni-sync` (adds `--dry-run` to its `omnictl` calls). `deploy.yaml`'s PR-time Omni plan does its own dry-run directly instead, since that check is read-only and diff-scoped.

`--chain <name>[,<name>...]` (comma-separated, no spaces; `<name>` must itself be a `JobTemplate`, not a `JobWorkflow` — a workflow already declares its own steps) builds an ad hoc, uncommitted workflow out of `<name>` plus the listed templates, applying `--arg`/`--cluster`/`--dry-run` to every step (there's no per-step override source without a committed `JobWorkflow`). In `-e remote` mode this goes through the exact same `JobWorkflowRun` machinery as running a named `JobWorkflow` — same log-following, same stop-at-first-failure. In `-e local` mode the listed playbooks just run sequentially against the same cloned checkout (cloned once per `hsctl run` invocation, not once per playbook) — no CRD/kro involved.

`deploy.yaml`'s merge-to-`main` Sync step relies on this: it runs `hsctl run omni-sync-and-bootstrap -e remote` (the committed workflow) so a push to `main` re-syncs Omni *and* re-bootstraps every cluster in one dispatch, with both steps' logs streamed into the same CI job.

Every `JobRun`/`JobWorkflowRun`/`Job` this creates is named after the `JobTemplate` actually being executed, not a bare step number (a chained hop is `<run>-step<N>-<templateRef>`) — so `kubectl get jobs`/pod names always tell you what's really running. Each is also labeled `REDACTED/job-owner`: the identity `hsctl` ran as, or `schedule` for a cron-triggered run — set once at the start of a chain and carried through every subsequent step. Ad hoc run names embed it too: `automatron-adhoc-<owner>-<name>-<timestamp>`. Your own identity resolves as, in order: `$HSCTL_JOB_OWNER` if set (`deploy.yaml` sets `HSCTL_JOB_OWNER=github-actions`); else the local-part of your OIDC `email` claim (e.g. `max` for `max@REDACTED`), read from the exec config already sitting in your local `core` kubectl context (no Infisical call — only a few people have Infisical access, but `-e remote` already requires a working `core` context, and the issuer URL/client ID aren't secret) and decoded from kubelogin's own cached token. There is **no local-username fallback**: if neither of those resolves (no `$HSCTL_JOB_OWNER` and no working `core` context yet), `hsctl run -e remote` fails outright with an error telling you to run `hsctl get kubeconfig core` first, rather than mislabeling the job with a `whoami` that likely doesn't match your `@REDACTED` identity. A Kyverno `ValidatingPolicy` (`require-automatron-job-owner-integrity`, `apps/kyverno`) checks this at admission time too — `jobOwner` must match your own authenticated identity (or the `job-owner` label), so it can't be spoofed by setting `$HSCTL_JOB_OWNER` yourself or hand-writing a CR; currently in `Audit` mode (logs violations, doesn't block) pending a check against real `@REDACTED` addresses.

Automatron authenticates to Infisical by reusing the k8s Infisical Operator's own identity (`INFISICAL_OPERATOR_CLIENT_ID`/`INFISICAL_OPERATOR_CLIENT_SECRET`), a credential only its pod has. Local runs of `bootstrap-core`/`bootstrap-cluster` can't reproduce that, so they pre-fetch the same secrets via your own `infisical login` CLI session (browser SSO) and hand them to Ansible directly. Any other playbook run locally gets no such handling — one that needs Infisical secrets has to add its own `hsctl_local`-aware fallback first (see `hsctl.d/run.sh`).

## Automatron job CRDs

Adding a new recurring or on-demand automatron job is a matter of committing a CR under `infra/automatron/` — no Helm changes needed. The tree is synced onto `core` by its own standalone ArgoCD Application (`clusters/core/automatron-jobs.yaml`), independent of `apps-core`, so a pending `REDACTED` CRD can never block anything else's sync.

| Directory | Kind | Purpose |
|-----------|------|---------|
| `infra/automatron/job-templates/` | `JobTemplate` | A playbook or script, optionally scheduled — includes the built-in `cleanup-old-runs` template (below) |
| `infra/automatron/job-workflows/` | `JobWorkflow` | An ordered list of `JobTemplate` steps, optionally scheduled |
| `infra/automatron/job-runs/` | `JobRun` | A one-off instance of a `JobTemplate` (rare to commit — most runs are ad hoc via `hsctl run` instead) |
| `infra/automatron/scripts/` | — | Bash/Python scripts referenced by `script`-runner `JobTemplate`s |

**Example — a scheduled playbook:**
```yaml
apiVersion: REDACTED/v1alpha1
kind: JobTemplate
metadata:
  name: my-playbook
spec:
  playbook: my-playbook    # infra/ansible/playbooks/my-playbook.yml
  schedule: "0 */2 * * *"  # omit entirely for an ad hoc/workflow-only template
```

**Example — a script-based template:**
```yaml
apiVersion: REDACTED/v1alpha1
kind: JobTemplate
metadata:
  name: my-script
spec:
  scriptPath: infra/automatron/scripts/my-script.sh
  scriptInterpreter: bash   # or python
```

| `JobTemplate` field | Type | Default | Description |
|----------------------|------|---------|-------------|
| `playbook` | string | `""` | Name under `infra/ansible/playbooks/`, minus `.yml`. Mutually exclusive with `scriptPath` — exactly one must be set |
| `scriptPath` | string | `""` | Repo path to an executable script, e.g. under `infra/automatron/scripts/` |
| `scriptInterpreter` | string | `bash` | `bash` or `python` |
| `schedule` | string | `""` | Cron schedule; omit for a template-only instance (never auto-fires, run via `JobRun`/`hsctl run` only) |
| `defaultArgs` | `map[string]string` | `{}` | Default extra-vars/script arguments, used for any key a `JobRun` doesn't override — e.g. `{cluster: boa1-prod}` |

**Example — an ordered workflow, one step with its own override:**
```yaml
apiVersion: REDACTED/v1alpha1
kind: JobWorkflow
metadata:
  name: my-workflow
spec:
  schedule: "*/15 * * * *"   # omit for ad hoc only, via `hsctl run`
  steps:
    - templateRef: my-playbook
    - templateRef: my-other-playbook
      args:
        cluster: boa1-prod   # always wins, even over `hsctl run --cluster ...`/`--arg cluster=...`
```

| `JobWorkflow` field | Type | Default | Description |
|----------------------|------|---------|-------------|
| `schedule` | string | `""` | Cron schedule; omit for an ad-hoc-only workflow |
| `steps` | `[]{templateRef, args, dryRun}` | — | Ordered list; `args`/`dryRun` are optional per-step overrides — see the precedence rule under `hsctl run`'s `--arg`/`--chain` above |

A workflow's steps run one after another — step 1 only starts once step 0's `Job` actually completes, chained by `apps/automatron/entrypoint.sh` (kro's own dependency graph can't express "wait for a Job to finish" across a variable-length list, so this part isn't kro-managed).

Every run of a `JobWorkflow` (scheduled or ad hoc) creates a `JobWorkflowRun` — the object to check for progress, rather than hunting down each step's `JobRun`/`Job` by label:

```
kubectl get jobworkflowrun --sort-by=.metadata.creationTimestamp
kubectl get jobworkflowrun my-workflow-run-1234567890 -o yaml   # .status.phase, .status.progress, .status.steps
```

`status.steps`/`status.phase`/`status.progress` (e.g. `"2/3"`) are projected by kro from the `JobRun`s labeled with that run's name — nothing to commit for this one, it's created automatically alongside step 0's `JobRun`. `JobWorkflow.status.recentRunNames` lists every run's name (unsorted — use `--sort-by` above for actual recency).

`kubectl get jobtemplate`/`jobrun`/`jobworkflow`/`jobworkflowrun` all show the fields above (plus, for `JobRun`/`JobWorkflowRun`, `.status.phase`/`Owner`, and for `JobWorkflow`, `.status.stepCount`/`.status.cronJobName`) directly in the printer columns — no need to drop to `-o yaml` for a quick status check.

Most one-off runs go through `hsctl run <name> -e remote` rather than a committed `JobRun` — see [`hsctl run`](#hsctl-run) above.

**Cleanup.** `Job`s (from both `JobTemplate` and `JobRun`) self-delete `automatron.jobTtlSeconds` after finishing (default 86400, in `apps/automatron/app.yaml`'s values) — standard Kubernetes `ttlSecondsAfterFinished`. `JobRun`/`JobWorkflowRun` CRs have no such native TTL, so the built-in `cleanup-old-runs` `JobTemplate` (`schedule: "0 3 * * *"`, `scripts/cleanup-old-runs.sh`) deletes ones older than `retentionDays` (default 7, `defaultArgs`) daily.

## `hsctl pim`

```
hsctl pim                                                            # interactive full-screen UI
hsctl pim activate <role|group|azure> <name|id> --reason "<justification>"
                   [--duration <e.g. 2h35m, 45m, or ISO8601 — default 8h>] [--access member|owner] [--scope <arm-scope>]
hsctl pim deactivate <role|group|azure> <name|id> [--scope <arm-scope>]
hsctl pim cancel <role|group> <request-id>
hsctl pim approve <role|group|azure> <approval-id> [--deny] [--reason "..."] [--scope <arm-scope>]
hsctl pim logout
```

Self-service [Entra ID](../architecture/teams.md) PIM actions from the CLI — listing lives under `hsctl get pimrole|pimgroup|pimazurerole|pimapproval` (see above). `role`/`group` (also `roles`/`groups`) hit Graph; `azure` hits ARM and requires `--scope`.

Bare `hsctl pim` opens an [fzf](https://github.com/junegunn/fzf)-based full-screen picker over your eligible/active/pending role+group items (arrow keys, enter to select, esc/ctrl-c to quit). Azure isn't in the UI yet.

Each item has a follow-up menu: Activate/Deactivate for your own assignments, Cancel for a pending request you sent, Approve/Deny for one you're the approver on. Pending rows show the requester's name, email, and request ID, labeled `pending · sent by you` or `pending · needs your approval`.

`activate role`/`activate group` print the resulting request ID, needed for `cancel`/`approve`. `approve` takes that same request ID (also shown by `hsctl get pimapprovals -o json` or the TUI) and resolves the pending approval step automatically — no separate step ID needed.

`approve role`/`approve group` hit Graph's `/beta` segment specifically, since `roleAssignmentApprovals`/`assignmentApprovals` have no `/v1.0` equivalent; every other `role`/`group` PIM call here uses `/v1.0`.

Requires `az`, `jq`, `curl`, `openssl`, `python3`, `infisical`, and `fzf` for the UI (same requirements apply to the `pim*` resources under `hsctl get`). `azure` auths via `az login`. `role`/`group` sign in separately through a dedicated `hsctl` Entra app registration (browser flow, token cached in macOS Keychain), since Azure CLI's own app can't get the Graph scopes PIM needs.

The tenant ID is hardcoded in `hsctl.d/get.sh` (not a secret, but scrubbed from the public mirror); the app's client ID (`CLIENT_ID` at `/hsctl`) is fetched from Infisical at runtime.

The `hsctl` app registration's delegated Graph permissions (all admin-consented) are `RoleManagement.ReadWrite.Directory`, `PrivilegedAccess.ReadWrite.AzureADGroup`, and `PrivilegedAccess.ReadWrite.AzureAD`. The last is only needed for `approve role`/`approve group`, since approvals sit behind the older PIM permission family rather than the unified `RoleManagement` one.

This app registration isn't Terraform-managed — permissions are added by hand in the Entra portal. After adding a new scope, run `hsctl pim logout` to drop the cached token so the next sign-in re-requests the updated scopes.

## `hsctl switch`

```
hsctl switch
```

Fuzzy-picker (requires [`fzf`](https://github.com/junegunn/fzf), `brew install fzf`) over both your existing local kubeconfig contexts and every cluster currently reachable via Tailscale (`hsctl get clusters`). Selecting a live cluster you don't have a context for yet runs `hsctl get kubeconfig` for you first. Switches with `kubectl config use-context` and prints the resulting default namespace.
