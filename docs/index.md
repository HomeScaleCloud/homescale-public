# HomeScale

HomeScale is a GitOps monorepo for private Kubernetes clusters running personal and family infrastructure. [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) watches this repo and reconciles all cluster state automatically on every merge to `main` — no manual `kubectl apply` required.

## Technology stack

| Layer | Tool | What it does |
|-------|------|-------------|
| OS / nodes | [Talos Linux](https://www.talos.dev/) | Immutable, API-driven Linux for Kubernetes nodes |
| Cluster lifecycle | [Omni](https://omni.siderolabs.com/) | SaaS control plane for provisioning and upgrading Talos clusters |
| GitOps | [ArgoCD](https://argo-cd.readthedocs.io/) | Continuous delivery; syncs cluster state from this repo |
| Secrets | [Infisical](https://infisical.com/) | Central secrets store; k8s operator syncs secrets into namespaces |
| Networking | [NetBird](https://netbird.io/) | Zero-trust WireGuard mesh for human and machine access |
| Node connectivity | [Talos KubeSpan](https://www.talos.dev/latest/talos-guides/network/kubespan/) | WireGuard tunnels between nodes across regions |
| DNS | [Cloudflare](https://developers.cloudflare.com/) | External DNS and tunnel ingress for public services |
| Backups | [VolSync](https://volsync.readthedocs.io/) + [restic](https://restic.net/) | PVC-level backup and restore |
| Container registry | [GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) | First-party images pushed on merge to `main` |

## Clusters

| Cluster | Region | Role |
|---------|--------|------|
| `mgmt` | — | Management: ArgoCD, Infisical operator, shared infra |
| `boa1-prod` | `boa1` | Production workloads |
| `boa1-gw` | `boa1` | Gateway: PXE boot, subnet routing, region ↔ mgmt bridge |

## How a change ships

```
PR opened → CI (scan + build) → merge to main → deploy CI (Terraform apply + Omni sync) → ArgoCD detects diff → reconciles cluster
```

See [Architecture overview](architecture/overview.md) for the full GitOps loop.

## Key docs

- [Architecture overview](architecture/overview.md) — GitOps flow, app catalog, CI/CD
- [Networking](architecture/networking.md) — KubeSpan, NetBird, internal/external service exposure
- [Secrets management](architecture/secrets.md) — Infisical, InfisicalSecret CRs, adding secrets
- [Deploying an app](operations/deploying-an-app.md) — step-by-step walkthrough for adding a new app
- [App reference](operations/apps.md) — full `app.yaml` field reference
- [Cluster operations](operations/clusters.md) — adding clusters, Omni templates, Terraform
- [Backups](operations/backups.md) — VolSync backup and restore
