# hsctl

`hsctl` is a small bash CLI for day-to-day operator tasks against the HomeScale fleet — listing clusters and machines, fetching kubeconfigs, browsing restic snapshots, power-cycling machines, jumping into ArgoCD, and managing Entra PIM assignments. Most commands talk to Omni and each cluster's API server over Tailscale, so they require an active Tailscale connection — the exception is `hsctl pim` and the `pim*` resources under `hsctl get`, which talk to Microsoft Graph/ARM directly and don't need Tailscale.

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
| `kubeconfig` | `hsctl get kubeconfig <cluster> [--omni\|--break-glass]` | Write a kubeconfig context for `<cluster>`. Default: [direct to the real apiserver](../architecture/networking.md#direct-cluster-api-access) with OIDC login (`kubectl-oidc_login`, [krew](https://krew.sigs.k8s.io/) plugin, required; OIDC issuer/client ID fetched from Infisical at `/k8s/oidc`). `--omni` runs `omnictl kubeconfig --cluster <cluster>`. `--break-glass` runs `omnictl kubeconfig --break-glass --cluster <cluster>` to bypass Omni and access nodes directly |
| `machines` | `hsctl get machines [--cluster <name>]` | List all Omni machines with power state, enriched with node name, cluster, and role for machines already assigned to a cluster. Filter to one cluster with `--cluster`/`-c` |
| `machine` | `hsctl get machine <id\|node-name>` | Show details for a single machine, by Omni machine ID or Kubernetes node name |
| `snapshot` | `hsctl get snapshot <app>` | List restic snapshots for an app's VolSync-backed PVC, with timestamps and IDs — see [Backups: restore procedure](../architecture/backups.md#restore-procedure) |
| `pimrole` | `hsctl get pimrole` | List your eligible + active Entra directory role PIM assignments (Graph API) |
| `pimgroup` | `hsctl get pimgroup` | List your eligible + active PIM-for-Groups assignments (Graph API) |
| `pimazurerole` | `hsctl get pimazurerole --scope <arm-scope>` | List your eligible + active Azure resource RBAC PIM assignments (ARM API) |
| `pimapproval` | `hsctl get pimapproval [role\|group\|azure] [--scope <arm-scope>]` | List pending PIM approval requests — both ones you can approve and your own, tagged `approver`/`requestor`, with the requester's display name and email (`role`/`group` only — Graph API). No type: `role` + `group` |

## `hsctl argocd`

```
hsctl argocd login <cluster>   # argocd CLI login via SSO to that cluster's ArgoCD
hsctl argocd open <cluster>    # open that cluster's ArgoCD UI in the browser
```

Both resolve to `argocd.<cluster>REDACTED` — the [Tailscale internal service address](../architecture/networking.md#internal-service-exposure) for ArgoCD on that cluster.

## `hsctl machine`

```
hsctl machine power on|off|reset [--force] <id|node-name>
```

Takes action directly against a physical machine — unlike `hsctl get`, this changes real hardware state. Accepts an Omni machine ID or a Kubernetes node name (resolved the same way as `hsctl get machine`).

| Action | Mechanism | Effect |
|--------|-----------|--------|
| `on` | `ipmitool chassis power on` | Power on |
| `off` | `talosctl shutdown` | Graceful OS shutdown (cordon/drain, then power off) |
| `off --force` | `ipmitool chassis power off` | Immediate hard power off, bypassing Talos |
| `reset` | `ipmitool chassis power reset` | Warm reset (equivalent to the physical reset button) |

`off` requires [`talosctl`](https://www.talos.dev/latest/introduction/getting-started/#talosctl) (`brew install talosctl`). If a graceful shutdown isn't possible or desired, pass `--force` to hard-cut power via IPMI instead — the previous behavior for `off`.

`on` and `reset` (and `off --force`) go over the BMC via IPMI (via [`ipmitool`](https://github.com/ipmitool/ipmitool), `brew install ipmitool`). Redfish was tried first, but this fleet's Supermicro BMCs gate every Redfish endpoint behind a paid `SUM DCMS OOB` license regardless of auth method — IPMI-over-LAN works unlicensed with the same credentials.

BMC connection info (`IP`, `VENDOR_USERNAME`, `VENDOR_PASSWORD`) is fetched at runtime from Infisical at `/bmc/<machine-id>` — this path must be populated per-machine before an IPMI-backed `hsctl machine power` action will work for it. Progress and outcome are reported via timestamped `INFO`/`ACTION`/`OK`/`ERROR` log lines (`hsctl_log_*` in `_lib.sh`) — the logging convention every future hsctl command that *takes action* (rather than just displaying data) should use.

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

Bare `hsctl pim` opens an [fzf](https://github.com/junegunn/fzf)-based full-screen picker over your eligible/active/pending role+group items (arrow keys, enter to select, esc/ctrl-c to quit), with a follow-up menu per item: Activate/Deactivate for your own assignments, Cancel for a pending request you sent, Approve/Deny for one you're the approver on — azure isn't in the UI yet. Pending rows show the requester (name + email) and request ID, and are labeled `pending · sent by you` or `pending · needs your approval` so the two directions aren't confused.

`activate role`/`activate group` print the resulting request ID, needed for `cancel`/`approve`. The ID `approve` takes is the same request ID (shown by `hsctl get pimapprovals -o json` or the TUI) — `hsctl pim approve` resolves the single pending approval step/stage against it automatically, no separate step ID needed. `approve role`/`approve group` hit Graph's `/beta` segment for this specifically (`roleAssignmentApprovals`/`assignmentApprovals` have no `/v1.0` equivalent); every other `role`/`group` PIM call in this repo uses `/v1.0`.

Requires `az`, `jq`, `curl`, `openssl`, `python3`, `infisical` (`fzf` too for the UI; same requirements apply to the `pim*` resources under `hsctl get`). `azure` auths via `az login`; `role`/`group` sign in separately (browser flow, token in macOS Keychain) through a dedicated `hsctl` Entra app registration, since Azure CLI's own app can't get the Graph scopes PIM needs. The tenant ID (`entra-tenant` at Infisical root) and the app's client ID (`CLIENT_ID` at `/hsctl`) are fetched at runtime, not hardcoded.

The `hsctl` app registration's delegated Graph permissions (all admin-consented) are `RoleManagement.ReadWrite.Directory`, `PrivilegedAccess.ReadWrite.AzureADGroup`, and `PrivilegedAccess.ReadWrite.AzureAD` — the last is only needed for `approve role`/`approve group`, since `roleAssignmentApprovals`/`assignmentApprovals` sit behind the older PIM permission family rather than the unified `RoleManagement`/`RoleAssignmentSchedule` one. This app registration isn't Terraform-managed; permissions are added by hand in the Entra portal. After adding a new scope, run `hsctl pim logout` to drop the cached token so the next sign-in re-requests the updated scope list.

## `hsctl switch`

```
hsctl switch
```

Fuzzy-picker (requires [`fzf`](https://github.com/junegunn/fzf), `brew install fzf`) over both your existing local kubeconfig contexts and every cluster currently reachable via Tailscale (`hsctl get clusters`). Selecting a live cluster you don't have a context for yet runs `hsctl get kubeconfig` for you first. Switches with `kubectl config use-context` and prints the resulting default namespace.
