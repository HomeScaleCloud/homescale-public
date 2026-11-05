# hsctl

`hsctl` is a small bash CLI for day-to-day operator tasks against the HomeScale fleet: listing clusters and Kubernetes nodes, fetching kubeconfigs, browsing restic snapshots, power-cycling machines, jumping into ArgoCD, and managing Entra PIM assignments.

Cluster discovery and normal kubeconfig selection use Tailscale and the cluster API proxies. Node queries use the active kubectl context and enrich matching nodes with live TOPF status. PIM commands talk directly to Microsoft Graph/ARM.

Source: `hsctl` (entrypoint) and `hsctl.d/*.sh` (command modules) at the repo root.

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

Output defaults to `table`; use `-o yaml` or `-o json` for scripting. Node JSON/YAML returns a list of concise records containing the table fields, including when filtering by name. `get clusters -o ansible` returns only reachable clusters. Ansible's own inventory independently reads committed `clusters/*/topf.yaml`, so initial bootstrap and outage handling never depend on discovery, an active kubeconfig or Omni.

| Resource | Usage | Description |
|----------|-------|-------------|
| `clusters` | `hsctl get clusters` | Discover online `tag:k8s` peers with `tag:env-<cluster>`, then verify their TLS API endpoints. Includes shared ingress proxies and clusters outside this checkout; offline or unhealthy APIs are excluded |
| `kubeconfig` | `hsctl get kubeconfig <cluster> [--break-glass]` | Select a reachable cluster and merge an OIDC context for its API proxy. Requires kubectl-oidc_login and OIDC settings from `/k8s/oidc`. `--break-glass` generates a short-lived TOPF admin context using the existing CA and can work from the LAN without Tailscale |
| `nodes` | `hsctl get nodes [name]` | Query the current kubectl context; columns: NAME, STAGE, READY, TYPE, ROLE, IP, IMAGE, SCHEMATIC, KERNEL, KUBELET, RUNTIME, AGE, UNMET CONDITIONS, ERROR |
| `snapshot` | `hsctl get snapshot <app>` | List restic snapshots for an app's VolSync-backed PVC, with timestamps and IDs — see [Backups: restore procedure](../architecture/backups.md#restore-procedure) |
| `pimrole` | `hsctl get pimrole` | List your eligible + active Entra directory role PIM assignments (Graph API) |
| `pimgroup` | `hsctl get pimgroup` | List your eligible + active PIM-for-Groups assignments (Graph API) |
| `pimazurerole` | `hsctl get pimazurerole --scope <arm-scope>` | List your eligible + active Azure resource RBAC PIM assignments (ARM API) |
| `pimapproval` | `hsctl get pimapproval [role\|group\|azure] [--scope <arm-scope>]` | List pending PIM approval requests: ones you can approve and your own, tagged `approver`/`requestor`, with the requester's display name and email (`role`/`group` only — Graph API). No type given: shows both `role` and `group` |

`STAGE` and `READY` come from TOPF's Talos machine status. Readiness is displayed as `✓` or `✗`, with `-` when unavailable. `TYPE` is control-plane when the standard Kubernetes control-plane/master role label exists, otherwise worker. `ROLE` comes from `REDACTED/role`; missing values show `-`. `IP` is the first InternalIP. `STAGE`, `READY`, `SCHEMATIC`, `UNMET CONDITIONS`, and `ERROR` come from `topf nodes -o yaml`, matched by InternalIP against `HSCTL_REPO_ROOT/clusters/*/topf.yaml`. Only matching inventory hosts are queried, using the existing TOPF secrets provider. The other columns come from node system information and creation time. Node queries never switch kubectl contexts.

The table abbreviates schematic IDs to eight characters plus `...` and joins unmet conditions with `; `. JSON/YAML uses keys `name`, `stage`, `ready`, `type`, `role`, `ip`, `image`, `schematic`, `kernel`, `kubelet`, `runtime`, `age`, `unmet_conditions`, and `error`. It keeps full schematic IDs, stores readiness as a boolean, and represents unmet conditions as a list of `name: reason` strings. An empty list means TOPF reported no unmet conditions; `null` means TOPF status was unavailable. Missing stages, readiness, schematics and errors are also `null`, displayed as `-` in the table. If TOPF cannot be queried, a warning goes to stderr and Kubernetes node output remains available.

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

Takes action directly against a physical machine — unlike `hsctl get`, this changes real hardware state. These older BMC commands still accept historical machine UUIDs; their node-name resolver remains Omni-based. They are separate from the Kubernetes node commands and Ansible inventory.

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

```bash
hsctl run <name> [--cluster <name>] [-e local|remote] [--git-ref <branch-or-tag>]
hsctl run bootstrap-cluster --cluster development -e local --nodes nodes.yaml
hsctl run topf --cluster development <topf arguments...>
hsctl run update-cluster --cluster development --dry-run
```

`bootstrap-cluster` installs cluster services; `--nodes` first provisions a new cluster's Talos control plane from the LAN. See [Clusters](../architecture/clusters.md) for node inventory, credential handling and recovery instructions. Run subsequent service-installation retries without `--nodes` after etcd has bootstrapped.

`topf` runs natively against `HSCTL_REPO_ROOT/clusters/<cluster>/topf.yaml` and the shared patches under infra/topf. All TOPF flags pass through, including apply --dry-run (exit 2 means changes). Missing CA bundles are restored from Infisical; routine calls use the private cache. Prefix --refresh-secrets to refresh deliberately or --init-secrets to restore/create and back up the first bundle. Generated configs and credentials contain secrets and must remain uncommitted. Bootstrap generates a fresh short-lived kubeconfig each run. `hsctl get kubeconfig <cluster> --break-glass` also generates a fresh TOPF admin context; default access continues to use OIDC.

`update-cluster` previews or reconciles the Talos/Kubernetes versions and remaining configuration declared in topf.yaml, locally or in CI. It requires data.bootstrapComplete true. See [Updates](../architecture/clusters.md#updates).

`terraform` plans/applies external infrastructure in `infra/terraform`; it does not provision Talos. Other names run matching playbooks from `infra/ansible/playbooks/` in local mode.

- `-e remote` (default) dispatches `deploy.yaml` through GitHub Actions and follows its result.
- `-e local` uses `HSCTL_REPO_ROOT`, including local changes, for the whole operation. Check out the desired branch and invoke its `./hsctl`. `--git-ref` is remote-only and selects the workflow revision (default `main`).
- `--dry-run` previews Terraform or update-cluster without applying changes. Bootstrap playbooks ignore it; it does not make a cluster bootstrap safe to preview.
- `--chain <name>[,...]` runs additional jobs against the same local checkout.
- `--arg key=value` passes extra arguments to remote generic playbooks; `--cluster` selects the cluster for bootstrap, updates or Terraform.

Local bootstrap reads ArgoCD and Infisical operator credentials through the authenticated Infisical CLI. Existing-cluster service installation also fetches the selected cluster's kubeconfig. A fresh `--nodes` bootstrap fetches kubeconfig after the API becomes ready. CI uses GitHub OIDC instead.

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
