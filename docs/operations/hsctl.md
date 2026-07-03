# hsctl

`hsctl` is a small bash CLI for day-to-day operator tasks against the HomeScale fleet — listing clusters and machines, fetching kubeconfigs, browsing restic snapshots, and jumping into ArgoCD. It talks to Omni and each cluster's API server over NetBird, so it requires an active NetBird connection.

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
| `machines` | `hsctl get machines [--cluster <name>]` | List all Omni machines, enriched with node name, cluster, and role for machines already assigned to a cluster. Filter to one cluster with `--cluster`/`-c` |
| `machine` | `hsctl get machine <id\|node-name>` | Show details for a single machine, by Omni machine ID or Kubernetes node name |
| `snapshot` | `hsctl get snapshot <app>` | List restic snapshots for an app's VolSync-backed PVC, with timestamps and IDs — see [Backups: restore procedure](../architecture/backups.md#restore-procedure) |

`machines`/`machine` join Omni's `MachineStatus` (network addresses, reachability) with `ClusterMachineIdentity` (node name, cluster, role) — see the underlying `omnictl get machinestatus` / `omnictl get clustermachineidentity` resources for the raw data.

## `hsctl argocd`

```
hsctl argocd login <cluster>   # argocd CLI login via SSO to that cluster's ArgoCD
hsctl argocd open <cluster>    # open that cluster's ArgoCD UI in the browser
```

Both resolve to `argocd-server.argocd.<cluster>REDACTED` — the [NetBird internal service address](../architecture/networking.md#internal-service-exposure) for ArgoCD on that cluster.

## `hsctl switch`

```
hsctl switch
```

Fuzzy-picker (requires [`fzf`](https://github.com/junegunn/fzf), `brew install fzf`) over both your existing local kubeconfig contexts and every cluster currently reachable via NetBird (`hsctl get clusters`). Selecting a live cluster you don't have a context for yet runs `hsctl get kubeconfig` for you first. Switches with `kubectl config use-context` and prints the resulting default namespace.
