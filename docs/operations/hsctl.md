# hsctl

`hsctl` is a small bash CLI for day-to-day operator tasks against the HomeScale fleet — listing clusters and machines, fetching kubeconfigs, browsing restic snapshots, power-cycling machines, and jumping into ArgoCD. It talks to Omni and each cluster's API server over NetBird, so it requires an active NetBird connection.

Source: `hsctl` (entrypoint) and `hsctl.d/*.sh` (one file per top-level command) at the repo root.

## Installing / updating

```bash
hsctl --update
```

Fetches the latest `hsctl` and `hsctl.d/*.sh` from the `main` branch of this repo via `gh api` and installs them to `~/.local/bin`. Run this after `hsctl` itself changes.

## `hsctl get`

```
hsctl get <resource> [-o table|yaml|json] [flags...]
```

Output format defaults to `table`; pass `-o yaml` or `-o json` for scripting.

| Resource | Usage | Description |
|----------|-------|-------------|
| `clusters` | `hsctl get clusters` | List Kubernetes clusters reachable via NetBird |
| `kubeconfig` | `hsctl get kubeconfig <cluster>` | Write a kubeconfig context for `<cluster>` (points at the cluster's NetBird-internal API server) |
| `machines` | `hsctl get machines [--cluster <name>]` | List all Omni machines with power state, enriched with node name, cluster, and role for machines already assigned to a cluster. Filter to one cluster with `--cluster`/`-c` |
| `machine` | `hsctl get machine <id\|node-name>` | Show details for a single machine, by Omni machine ID or Kubernetes node name |
| `snapshot` | `hsctl get snapshot <app>` | List restic snapshots for an app's VolSync-backed PVC, with timestamps and IDs — see [Backups: restore procedure](../architecture/backups.md#restore-procedure) |

## `hsctl argocd`

```
hsctl argocd login <cluster>   # argocd CLI login via SSO to that cluster's ArgoCD
hsctl argocd open <cluster>    # open that cluster's ArgoCD UI in the browser
```

Both resolve to `argocd-server.argocd.<cluster>REDACTED` — the [NetBird internal service address](../architecture/networking.md#internal-service-exposure) for ArgoCD on that cluster.

## `hsctl machine`

```
hsctl machine power on|off|reset <id|node-name>
```

Takes action directly against a physical machine's BMC over IPMI (via [`ipmitool`](https://github.com/ipmitool/ipmitool), `brew install ipmitool`) — unlike `hsctl get`, this changes real hardware state. Accepts an Omni machine ID or a Kubernetes node name (resolved the same way as `hsctl get machine`).

| Action | `ipmitool chassis power` | Effect |
|--------|---------------------------|--------|
| `on` | `on` | Power on |
| `off` | `off` | Immediate hard power off |
| `reset` | `reset` | Warm reset (equivalent to the physical reset button) |

Redfish was tried first, but this fleet's Supermicro BMCs gate every Redfish endpoint behind a paid `SUM DCMS OOB` license regardless of auth method — IPMI-over-LAN works unlicensed with the same credentials.

BMC connection info (`IP`, `VENDOR_USERNAME`, `VENDOR_PASSWORD`) is fetched at runtime from Infisical at `/bmc/<machine-id>` — this path must be populated per-machine before `hsctl machine power` will work for it. Progress and outcome are reported via timestamped `INFO`/`ACTION`/`OK`/`ERROR` log lines (`hsctl_log_*` in `_lib.sh`) — the logging convention every future hsctl command that *takes action* (rather than just displaying data) should use.

## `hsctl switch`

```
hsctl switch
```

Fuzzy-picker (requires [`fzf`](https://github.com/junegunn/fzf), `brew install fzf`) over both your existing local kubeconfig contexts and every cluster currently reachable via NetBird (`hsctl get clusters`). Selecting a live cluster you don't have a context for yet runs `hsctl get kubeconfig` for you first. Switches with `kubectl config use-context` and prints the resulting default namespace.
