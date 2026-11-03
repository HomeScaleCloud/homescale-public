# Clusters

TOPF manages Talos machine configuration. Ansible orders initial bootstrap and installs Infisical credentials, Cilium and ArgoCD. Each cluster self-hosts ArgoCD. Terraform manages external services; Talos credentials never enter Terraform state.

## Inventory and shared policy

| Path | Purpose |
|------|---------|
| `clusters/<cluster>/topf.yaml` | Version pins, SecureBoot schematic, endpoint, CIDRs and permanent node inventory |
| `infra/topf/all/` | Shared installation, network, identity, kubelet and optional storage patches |
| `infra/topf/control-plane/` | etcd, OIDC, Cilium prerequisites, scheduling and optional VIP patches |
| `infra/topf/secrets-provider.sh` | Native TOPF provider backed by Infisical and a private local cache |
| `clusters/<cluster>/apps.yaml` | ArgoCD app-of-apps; recursively syncs the cluster directory, excluding `topf.yaml` |

Cluster-wide settings live under `data`: node subnet, bond NICs, installation disk, gateway, DNS, pod/service CIDRs and optional platform features. Node entries contain an inventory alias (`host`), permanent IP, role and any node label. Talos generates stable `talos-…` hostnames; the aliases select TOPF nodes and name rendered files. Kubernetes inventory checks use permanent IPs instead of assuming aliases equal hostnames. A node can override the installation disk in its own data when necessary.

The shared network patch contains the native BondConfig, VLANConfig and ResolverConfig documents. It creates bond1 addresses from each node's IP and the nodeSubnet prefix, applies the cluster gateway/DNS/NICs, and creates VLANs 241 and 271. There are no repeated network documents or YAML anchors in node inventory. Edit the shared patch when changing network policy.

`data.nodeSubnet` is the node LAN CIDR. Kubelet and etcd use it to select node addresses; Terraform reads the same value for Tailscale LAN access and route auto-approval. Actual Tailscale advertisement remains in apps.yaml.

Ordinary TOPF render/apply commands automatically select every applicable patch. There is no hardware discovery, Helm dependency, vendored library, modeline or generated config to commit.

Legacy Talm `nodes/` configs, cluster `Chart.lock` files and Helm archives are obsolete. Remove them when updating an existing checkout. Keep `secrets.yaml`: TOPF reuses that CA bundle. Old generated `talosconfig` files can be regenerated with `hsctl run topf --cluster <name> talosconfig`.

Both clusters use bond1 to avoid the kernel-created bond0, LACP, storage VLAN 241 and media VLAN 271. Production retains its four-NIC bonds, API VIP, role labels, Longhorn volume and Spegel containerd setting. Development uses two NICs. Spegel requires at least three nodes. Installer schematic and version pins retain the existing SecureBoot image.

Production uses `/dev/nvme0n1` for installation on all three control-plane nodes. The old boa1-prod configuration selected NVMe disks, and the disk path was confirmed during this migration. Its gateway and DNS still need confirmation and remain omitted. Rendering that inventory fails; validation substitutes clearly identified temporary fixtures only for missing settings. CI applies default to disabled until data.bootstrapComplete is explicitly true.

ArgoCD recursively syncs arbitrary Kubernetes YAML/JSON manifests under `clusters/<cluster>/`, excluding only `topf.yaml`. Generated Talos configs and credentials stay gitignored. If an existing Application still points to the old `apps/` directory, reapply the moved `apps.yaml` once to update its source path.

## Credentials and execution

Infisical stores the existing SECRETS_YAML CA bundle at /k8s/talos/prod and /k8s/talos/dev, both in environment prod. Folders remain manually managed. TOPF consumes the same Talos bundle directly; this migration does not rotate CAs or change the bundle format.

`hsctl run topf --cluster <name> ...` invokes native TOPF in the cluster directory. The provider restores a missing local secrets.yaml; ordinary operations then use that private, gitignored cache without repeated remote reads. Prefix --refresh-secrets before the TOPF subcommand to fetch the current backup deliberately.

First use requires explicit initialization:

```bash
hsctl run topf --cluster development --init-secrets --confirm=false secrets >/dev/null
```

This restores the remote bundle first. If none exists, it backs up an existing local bundle or creates and backs up a new one. Credentials without a recoverable bundle cause failure. Never delete a bundle to fix authentication. A failed backup leaves secrets.pending.yaml; repeat initialization to upload that same bundle before proceeding. Export/authentication failures stop the operation; they never trigger CA generation. The provider uses the existing Infisical CLI session/token without triggering login or project setup. Local bundles are mode 0600; symlinks, competing local writes and mismatches with the remote bundle are refused. Resolve differing bundles manually after verifying the correct CA. Run first initialization from one machine at a time.

CI supplies a read-only private bundle via HSCTL_TOPF_SECRETS_FILE. It cannot generate or upload cluster secrets. Client credentials are disposable: topf talosconfig and topf kubeconfig generate them from the bundle. Bootstrap creates a fresh 12-hour admin kubeconfig for each run, then deletes it and rendered machine configs on success or failure. Full renders contain secrets and must remain private and uncommitted. Existing remote TALOSCONFIG/KUBECONFIG values can remain for recovery; TOPF does not depend on them.

Local operations use HSCTL_REPO_ROOT, including uncommitted changes. Invoke the checked-out branch's ./hsctl; --git-ref selects remote workflow revisions only.

## Bootstrap: adding a new cluster

The first bootstrap runs from the LAN. Tailscale subnet routing is an ArgoCD workload and cannot provide initial connectivity.

1. Complete topf.yaml, including the real install disk, node subnet, bond NICs, gateway and DNS. Keep pod/service CIDRs unique across clusters.
2. Boot matching Image Factory SecureBoot media. Confirm maintenance-mode access and SecureBoot with `talosctl --nodes <dhcp-ip> get securitystate --insecure`.
3. Write an uncommitted nodes.yaml listing every control-plane node:

   ```yaml
   - name: development-1
     dhcp_ip: 10.1.247.219
     static_ip: 10.1.247.21
   ```

4. Run `./hsctl run bootstrap-cluster --cluster development -e local --nodes nodes.yaml`.
5. Confirm bootstrap, ArgoCD sync and Tailscale connectivity. Set `data.bootstrapComplete: true` in topf.yaml once those checks succeed to enable declarative CI updates.

The bootstrap names and permanent addresses must match the aliases and IPs in topf.yaml. Bootstrap backs up the CA, renders offline from permanent configuration, applies through each DHCP address with native talosctl --insecure, waits for permanent Talos addresses, and then uses authenticated TOPF bootstrap at the first permanent address. It waits for the Kubernetes API, generates fresh credentials and installs cluster services. Existing etcd membership is detected by TOPF's bootstrap operation.

After Talos bootstrap succeeds, retry service installation without --nodes to avoid replaying the maintenance-mode apply.

## Later applies and additional nodes

```bash
hsctl run topf --cluster development render
hsctl run topf --cluster development apply --dry-run
hsctl run topf --cluster development apply
```

Native dry-run exit code 2 means changes were detected; CI treats it as a successful preview. Source inventory and shared patches determine the entire configuration. Generated output is private and gitignored.

For a new node, add its inventory alias, permanent IP and role to the inventory, render to a private directory, then apply that node's file to its maintenance-mode DHCP address using talosctl --insecure. Once it answers at its permanent IP, use TOPF's --nodes-filter '^alias$' for later operations. Do not initialize new cluster secrets or bootstrap etcd for an additional node. See [Registering new machines](../operations/registering-machines.md).

CI performs read-only previews on PRs and applies on merge only after bootstrapComplete. It never auto-bootstraps. The required check display names scan / Talm and deploy / Talm Gate remain for compatibility with the existing GitHub ruleset; both execute TOPF checks now.

## Updates

Renovate tracks `talosVersion` and `kubernetesVersion` in each topf.yaml, plus the TOPF CLI pin in the installer. These dependencies get separate PRs and never auto-merge. Review release notes, the supported Talos/Kubernetes combination, etcd snapshots and application backups before merging a version bump. Development has one node, so upgrades cause downtime.

`infra/ansible/playbooks/update-cluster.yml` reconciles the versions declared in Git:

1. On a PR that changes an inventory, shared patches or upgrade code, CI reads live state and posts native Talos/Kubernetes upgrade plans plus a redacted config preview. It never upgrades, drains or applies in preview mode.
2. On every main deployment, CI reconciles all bootstrapped clusters, even when the commit did not change topf.yaml. When both clusters are selected, development runs before production; any failure stops the run.
3. TOPF upgrades Talos to the desired SecureBoot installer/schematic, drains one node at a time and waits for recovery. PodDisruptionBudgets remain enforced.
4. If Kubernetes versions differ, `talosctl upgrade-k8s --to <desired version>` orchestrates control-plane components and kubelets. One control-plane API entry addresses the whole cluster. Every replica is inspected so an interrupted rollout can resume even when the API already reports the target version.
5. Every running version must match Git before `topf apply` reconciles the remaining configuration. This prevents a normal config apply from bypassing Kubernetes upgrade orchestration. The final check requires reachable, Ready nodes.

The playbook refuses downgrades and skips across minor releases, keeps native compatibility checks enabled, and stops if anything fails. If a Kubernetes preview is rejected because the installed Talos is too old, merge a Talos-only bump first, then rerun the Kubernetes PR. Use separate PRs to maintain a supported intermediate combination; CI does not bypass those checks.

Nothing upgrades when a pin already matches the running version (unless the Talos schematic changed); ordinary configuration is still reconciled. Retries discover live state and finish outstanding work. CI only reads the existing Infisical CA bundle, generates private short-lived client configs and removes its workspace on success or failure. It never initializes secrets or bootstraps etcd. Both inventories currently remain disabled until their first bootstrap is confirmed with `data.bootstrapComplete: true`.

To run the same procedure explicitly:

```bash
# GitHub Actions, desired pins from the selected branch (main by default):
hsctl run update-cluster --cluster development --dry-run
hsctl run update-cluster --cluster development

# From the LAN using the current checkout and existing local CA cache/session:
./hsctl run update-cluster --cluster development -e local --dry-run
./hsctl run update-cluster --cluster development -e local
```

App chart/image updates continue through Renovate and ArgoCD. Direct TOPF commands remain available for inspecting nodes and specialized maintenance; use update-cluster for version changes.

## Operational limits

Schedule etcd snapshots separately from VolSync application backups.

Regression tests in `tests/` cover native Talos schemas, shared network policy, installation, platform patches, worker roles, CIDR uniqueness, secret recovery and bootstrap ordering/cleanup. Production hardware validation uses temporary fixtures until its missing values are confirmed. Offline tests cannot establish successful disk installation, LACP convergence or live cluster health.
