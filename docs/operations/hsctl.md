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
hsctl run <name> [--cluster <name>] [-e|--execution-mode local|remote] [--dry-run]
```

Runs a playbook or script via [automatron](../architecture/overview.md#automatron--kro-backed-job-runner) (the in-cluster runner on `core`), or locally. `<name>` is required (no "run everything" shortcut).

In `-e remote` mode (the default), `<name>` is the name of an `AutomatronJobTemplate` or `AutomatronJobWorkflow` custom resource — these are the CRDs [kro](https://kro.run) generates from the `ResourceGraphDefinition`s shipped in `apps/automatron/templates/`; the actual instances live under `infra/automatron/job-templates/` and `infra/automatron/workflows/`. `hsctl` checks for a matching `JobTemplate` first, then a `JobWorkflow`:

| Kind | Effect |
|------|--------|
| `JobTemplate` | Runs it directly — one `JobRun` CR, one `Job`. `--cluster`/`--dry-run` override the template's own `spec.defaultCluster`/nothing (templates don't have a stored dry-run default) |
| `JobWorkflow` | Creates a `JobWorkflowRun` (tracks the whole execution's progress — see below) plus a `JobRun` for its first step (`spec.steps[0]`); on success, automatron chains the remaining steps itself by creating the next `JobRun` (see `apps/automatron/entrypoint.sh`) — same as a scheduled workflow run. `--cluster`/`--dry-run` override step 0 only, not later steps |

Three `JobTemplate`s ship pre-migrated from the old Ansible-only setup (`infra/automatron/job-templates/{omni-sync,bootstrap-cluster,bootstrap-core}.yaml`), none scheduled on their own — `bootstrap-cluster` takes `--cluster <name>` (its Omni cluster ID, e.g. `boa1-prod`); `bootstrap-core` ignores it. The `omni-sync-and-bootstrap` `JobWorkflow` (`infra/automatron/workflows/`) runs both every 15 minutes and is also the target for an ad hoc "sync and bootstrap everything" run.

`-e`/`--execution-mode` is `local` or `remote` (default `remote`):

- **`remote`** applies a `JobRun` CR on automatron in the `core` cluster, waits for kro to materialize the underlying `Job`, and streams its logs immediately. Requires a Tailscale-reachable `core` apiserver (same as `hsctl switch`/`hsctl get kubeconfig`) and `team-infra-plat`/`team-sec-plat` membership — no PIM needed. If a `core` kubectl context already exists (e.g. CI pre-seeds one from `CORE_KUBECONFIG`), it's reused as-is instead of triggering an interactive OIDC login.
- **`local`** treats `<name>` as an Ansible playbook filename (minus `.yml`) under `infra/ansible/playbooks/` — no `JobTemplate`/`JobWorkflow` lookup, since kro/automatron aren't involved. Clones `HomeScaleCloud/homescale@main` fresh into a temp directory (`gh repo clone`, requires `gh auth login`) and runs `ansible-playbook` against that checkout, cleaning it up afterward — never against whatever's checked out locally, which could be a branch, stale, or have uncommitted changes. Still needed for the very first core bootstrap, before automatron exists, or for disaster recovery if automatron itself is down.

`--dry-run` is only meaningful for playbooks that act on it — currently just `omni-sync` (adds `--dry-run` to its `omnictl` calls). `deploy.yaml`'s PR-time Omni plan does its own dry-run directly instead, since that check is read-only and diff-scoped.

`deploy.yaml`'s merge-to-`main` Sync step runs `hsctl run omni-sync -e remote` then `hsctl run bootstrap-cluster -e remote` as two explicit calls (not the `omni-sync-and-bootstrap` workflow) so the CI job blocks on and streams logs for both steps — the workflow's own step-chaining is fire-and-forget, fine for the unattended scheduled run but not for a CI gate.

Automatron authenticates to Infisical by reusing the k8s Infisical Operator's own identity (`INFISICAL_OPERATOR_CLIENT_ID`/`INFISICAL_OPERATOR_CLIENT_SECRET`), a credential only its pod has. Local runs of `bootstrap-core`/`bootstrap-cluster` can't reproduce that, so they pre-fetch the same secrets via your own `infisical login` CLI session (browser SSO) and hand them to Ansible directly. Any other playbook run locally gets no such handling — one that needs Infisical secrets has to add its own `hsctl_local`-aware fallback first (see `hsctl.d/run.sh`).

## Automatron job CRDs

Adding a new recurring or on-demand automatron job is a matter of committing a CR under `infra/automatron/` — no Helm changes needed. The tree is recursively synced onto `core` as a raw source on `clusters/core/apps.yaml`'s `apps-core` Application.

| Directory | Kind | Purpose |
|-----------|------|---------|
| `infra/automatron/job-templates/` | `JobTemplate` | A playbook or script, optionally scheduled |
| `infra/automatron/workflows/` | `JobWorkflow` | An ordered list of `JobTemplate` refs, optionally scheduled |
| `infra/automatron/job-runs/` | `JobRun` | A one-off instance of a `JobTemplate` (rare to commit — most runs are ad hoc via `hsctl run` instead) |
| `infra/automatron/scripts/` | — | Bash/Python scripts referenced by `script`-runner `JobTemplate`s |

**Example — a scheduled playbook:**
```yaml
apiVersion: REDACTED/v1alpha1
kind: JobTemplate
metadata:
  name: my-playbook
  namespace: automatron
spec:
  playbook: my-playbook   # infra/ansible/playbooks/my-playbook.yml
  schedule: "0 */2 * * *" # omit entirely for an ad hoc/chained-only template
```

**Example — a script-based template:**
```yaml
apiVersion: REDACTED/v1alpha1
kind: JobTemplate
metadata:
  name: my-script
  namespace: automatron
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
| `defaultCluster` | string | `""` | Default `--cluster`-equivalent target, used when a `JobRun` doesn't override it |

**Example — an ordered workflow:**
```yaml
apiVersion: REDACTED/v1alpha1
kind: JobWorkflow
metadata:
  name: my-workflow
  namespace: automatron
spec:
  schedule: "*/15 * * * *"   # omit for ad hoc only, via `hsctl run`
  steps:
    - templateRef: my-playbook
    - templateRef: my-script
      cluster: boa1-prod
      dryRun: false
```

A `JobWorkflow`'s steps run one after another — step 1 only starts once step 0's `Job` actually completes, chained by `apps/automatron/entrypoint.sh` (kro's own dependency graph can't express "wait for a Job to finish" across a variable-length list, so this part isn't kro-managed).

Every run of a `JobWorkflow` (scheduled or ad hoc) creates a `JobWorkflowRun` — the object to check for progress, rather than hunting down each step's `JobRun`/`Job` by label:

```
kubectl get jobworkflowrun -n automatron -l REDACTED/workflow=my-workflow --sort-by=.metadata.creationTimestamp
kubectl get jobworkflowrun my-workflow-run-1234567890 -n automatron -o yaml   # .status.phase, .status.steps
```

`status.steps` and `status.phase` (`Running`/`Succeeded`/`Failed`) are projected by kro from the `Job`s labeled with that run's name — nothing to commit for this one, it's created automatically alongside step 0's `JobRun`. `JobWorkflow.status.recentRunNames` lists every run's name (unsorted — use `--sort-by` above for actual recency).

Most one-off runs go through `hsctl run <name> -e remote` rather than a committed `JobRun` — see [`hsctl run`](#hsctl-run) above.

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
