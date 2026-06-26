# HomeScale

!!! warning "Work in progress"
    This documentation was recently bootstrapped and is largely AI-generated from the repository. As a result, some pages may be incomplete, imprecise, or lag behind recent changes. Over time, the docs will be reviewed, corrected, and expanded until they become a reliable reference. For now, treat the repository itself as the source of truth.

[HomeScaleCloud/homescale](https://github.com/HomeScaleCloud/homescale) is a GitOps monorepo for Kubernetes clusters and supporting infrastructure.

## Technology stack

### Infrastructure

| Tool | What it does |
|------|-------------|
| [Kubernetes](https://kubernetes.io/) | Workload and container orchestration |
| [Talos Linux](https://www.talos.dev/) | Immutable, API-driven OS for Kubernetes nodes |
| [Omni](https://omni.siderolabs.com/) | Talos cluster lifecycle management (provisioning, upgrades) |
| [Terraform](https://developer.hashicorp.com/terraform) | Cloud and provider resource provisioning |
| [Ansible](https://www.ansible.com/) | Bootstrapping and firmware/configuration management |

### Networking & security

| Tool | What it does |
|------|-------------|
| [NetBird](https://netbird.io/) | Zero-trust WireGuard mesh for human and machine access |
| [Cloudflare](https://developers.cloudflare.com/) | External DNS and tunnel ingress for public services |
| [Entra ID](https://www.microsoft.com/en-us/security/business/identity-access/microsoft-entra-id) | Identity and access management (SAML/SSO) |
| [Infisical](https://infisical.com/) | Secrets management; k8s operator syncs secrets into namespaces |
| [VolSync](https://volsync.readthedocs.io/) + [restic](https://restic.net/) | PVC-level backup and restore |

### GitOps & automation

| Tool | What it does |
|------|-------------|
| [ArgoCD](https://argo-cd.readthedocs.io/) | GitOps continuous delivery for Kubernetes |
| [GitHub Actions](https://github.com/features/actions) | CI/CD (scan, build, deploy workflows) |
| [Renovate](https://docs.renovatebot.com/) | Automated dependency updates |
| `hsctl` | CLI for common operator tasks (machine listing, VolSync snapshots, ArgoCD login) |

## Cluster types

Three distinct cluster "roles" exist:

| Type | Example | Description |
|------|---------|-------------|
| `mgmt` | `mgmt` | A single managed [DigitalOcean Kubernetes](https://docs.digitalocean.com/products/kubernetes/) cluster. Exists solely to run [Omni](https://omni.siderolabs.com/) |
| `*-gw` | `boa1-gw` | Single-node Talos cluster per physical region. Gives Omni bare-metal provisioning connectivity (PXE boot, BMC/MGMT subnet routing) into that region |
| everything else | `boa1-prod` | General compute clusters running actual workloads, managed by Omni via the gateway for their region |

## How a change ships

```
PR opened → CI (scan + build) → merge to main → deploy CI (Terraform apply + Omni sync) → ArgoCD detects diff → reconciles cluster
```

See [Architecture overview](architecture/overview.md) for the full GitOps loop.

## Key docs

- [Architecture overview](architecture/overview.md) — GitOps flow, app catalog, CI/CD
- [Networking](architecture/networking.md) — NetBird, internal/external service exposure
- [Secrets management](architecture/secrets.md) — Infisical, InfisicalSecret CRs, adding secrets
- [Deploying an app](operations/deploying-an-app.md) — step-by-step walkthrough for adding a new app
- [App reference](operations/apps.md) — full `app.yaml` field reference
- [Cluster operations](operations/clusters.md) — adding clusters, Omni templates, Terraform
- [Backups](operations/backups.md) — VolSync backup and restore
