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
hsctl get <resource> [-o table|yaml|json|ansible] [flags...]
```

Output format defaults to `table`; pass `-o yaml` or `-o json` for scripting. `-o ansible` is only meaningful for `clusters`/`machines` — it's what `infra/ansible/inventory/clusters`/`machines` (Ansible dynamic inventory scripts) call under the hood, so ansible-playbook always sees the same live Omni state `hsctl get` itself would show.

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
hsctl run <name> [--cluster <name>] [--arg key=value]... [-e|--execution-mode local|remote] [--dry-run] [--chain <name>[,<name>...]] [--git-ref <ref>]
```

Runs a playbook or script, either remotely (dispatches [`.github/workflows/deploy.yaml`](../architecture/overview.md#cicd-pipeline) via `gh workflow run` and follows the triggered run) or locally (clones `main` fresh and runs it directly against that checkout). `<name>` is required (no "run everything" shortcut), and is one of:

| `<name>` | Runs | Notes |
|----------|------|-------|
| `bootstrap-core` | `infra/ansible/playbooks/bootstrap-core.yml` | Bootstraps the `core` cluster |
| `bootstrap-cluster` | `infra/ansible/playbooks/bootstrap-cluster.yml` | Bootstraps workload clusters (all, or one via `--cluster`) |
| `omni-sync` | `infra/omni/sync.sh` | Syncs cluster templates + machine classes into Omni |
| `terraform` | `infra/terraform/plan-apply.sh` | Plans/applies `infra/terraform` — the only way to bootstrap `core` itself, before CI can reach it over Tailscale |
| anything else | `infra/ansible/playbooks/<name>.yml` | **Local mode only** — any other committed playbook |

`-e`/`--execution-mode` is `local` or `remote` (default `remote`):

- **`remote`** runs `gh workflow run deploy.yaml` (requires `gh auth login` and write access to `HomeScaleCloud/homescale`) with `job`/`cluster`/`machineclasses`/`dry_run`/`extra_args` inputs built from `<name>`/`--cluster`/`--arg`/`--dry-run`, waits for the resulting run to appear, then follows it with `gh run watch --exit-status`. `terraform`/`omni-sync` dispatch to those jobs directly (`inputs.job`); anything else dispatches to the `ansible` job's generic-playbook fallback.
- **`local`** clones `HomeScaleCloud/homescale@main` fresh into a temp directory (`gh repo clone`, requires `gh auth login`) and runs `<name>` directly against that checkout, cleaning it up afterward — never against whatever's checked out locally, which could be a branch, stale, or have uncommitted changes. Still needed for the very first core bootstrap, or any time CI/Tailscale can't yet reach what you're changing — `terraform -e local` is in fact the *only* way to stand up `core` itself.

`--arg key=value` (repeatable, remote mode only): `cluster`/`machineclasses` fold into the matching workflow_dispatch input; anything else is joined into `extra_args` (space-separated `key=value`), which only the generic-ansible-playbook fallback job consumes as extra `-e key=value` flags. `--cluster <name>` is sugar for `--arg cluster=<name>` — meaningful for `bootstrap-cluster` (`-e target=<name>`), `terraform` (scopes the plan/apply to that cluster's own resources — computed from an untargeted plan's own JSON output, not `terraform state list`, so it still catches a not-yet-created resource), and `omni-sync` (syncs just that one cluster).

`--dry-run`: `terraform` plans only (no apply); `omni-sync` adds `--dry-run` to its `omnictl` calls; ignored by ansible playbooks.

`--chain <name>[,...]` is **local mode only** — it runs `<name>` plus the listed templates (comma-separated, no spaces) in sequence against the same cloned checkout. Not supported in `-e remote` mode: GitHub Actions' `workflow_dispatch` can't compose an arbitrary step sequence at dispatch time, so `hsctl run --chain ... -e remote` fails outright with an error telling you to dispatch each one separately instead.

`--git-ref <ref>` (remote mode only, default `main`) is passed straight through as `gh workflow run deploy.yaml --ref <ref>` — the whole workflow (not just one job) checks out that ref. The one real use is planning a PR's own branch instead of `main`'s current content.

`bootstrap-core`/`bootstrap-cluster` run locally pre-fetch `/k8s/argocd/deploy-key`, `/k8s/infisical`, and (`bootstrap-core` only) `/ci`'s `CORE_KUBECONFIG` via your own already-authenticated `infisical` CLI session, handing them to Ansible directly (see `_run_bootstrap_local` in `hsctl.d/run.sh`) — Ansible's own Infisical login (GitHub OIDC in CI) is skipped entirely. `terraform -e local` gets the analogous treatment for its own Infisical universal-auth credentials (`INFISICAL_CI_CLIENT_ID`/`_SECRET`, `INFISICAL_ORG_ID`, `CLOUDFLARE_API_TOKEN`, `TF_TOKEN_app_terraform_io`), fetched from `/ci` and exported directly into `plan-apply.sh`'s environment (see `_run_terraform_local`). `omni-sync -e local` has no special secrets handling — `OMNI_SERVICE_ACCOUNT_KEY` is picked up the same way `hsctl get`/`hsctl machine` already resolve Omni access. Any other playbook run locally gets no such handling either.

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
