# Team Ownership

HomeScale is maintained by two platform teams. This page records which team owns each component and what that means for code review.

## Teams

| Team | GitHub | Mandate |
|------|--------|---------|
| Infrastructure Platforms | `@HomeScaleCloud/team-infra-plat` | Compute, networking, storage, observability, GitOps machinery, and cluster lifecycle |
| Security Platforms | `@HomeScaleCloud/team-sec-plat` | Identity and SSO (Entra ID), secrets, access control policy, and public cloud security posture |

CODEOWNERS is configured in `.github/CODEOWNERS`. All paths default to Infrastructure Platforms; Security Platforms overrides apply to its specific directories.

---

## Infrastructure Platforms

### Kubernetes platform

| App | What it does |
|-----|-------------|
| `cilium` | CNI / eBPF network dataplane |
| `multus` | Secondary network interfaces |
| `descheduler` | Workload rebalancing |
| `node-feature-discovery` | Hardware label propagation |
| `generic-device-plugin-tun` | TUN device plugin |
| `kubelet-serving-cert-approver` | Auto-approval of kubelet serving certs |
| `spegel` | Peer-to-peer image distribution |

### GitOps & delivery

| App / Path | What it does |
|------------|-------------|
| `argocd` | Continuous delivery engine |
| `.github/workflows/` | CI/CD pipelines (scan, build, deploy) |

### Networking & ingress

NetBird is the zero-trust WireGuard mesh that connects all clusters, CI jobs, and end-user devices. Infrastructure Platforms owns the mesh topology, network resource definitions, and the Terraform that creates NetBird groups and access policies. External services are exposed via a Cloudflare tunnel or reverse proxy, with DNS managed automatically by external-dns.

| App | What it does |
|-----|-------------|
| `netbird` / `netbird-crs` | Zero-trust WireGuard mesh and network resources |
| `cloudflared` | Cloudflare tunnel for external exposure |
| `traefik-private` / `traefik-public` | Ingress controllers |
| `external-dns` / `external-dns-crs` | Automatic DNS record management |

### TLS

| App | What it does |
|-----|-------------|
| `cert-manager` / `cert-manager-crs` | Certificate issuance and renewal |

### Storage & backup

| App | What it does |
|-----|-------------|
| `longhorn` | Distributed block storage |
| `volsync` | PVC backup and restore via restic |

### Observability

Infrastructure Platforms owns the full observability stack: per-cluster Prometheus instances feed into a central aggregation layer with Grafana, Alertmanager, and Loki. All PrometheusRule alerts and their runbooks are Infrastructure Platforms's to author and maintain.

| App | What it does |
|-----|-------------|
| `metrics` | Per-cluster kube-prometheus-stack |
| `metrics-aggr` | Central aggregation, Grafana, Alertmanager, Loki |

### Cluster lifecycle

Infrastructure Platforms owns the full lifecycle of every cluster: bare-metal provisioning via PXE boot (Omni infra provider), Talos OS config patches, Kubernetes version upgrades, and the bootstrap app-of-apps that seeds ArgoCD on a fresh cluster. Gateway clusters (`*-gw`) are also Infrastructure Platforms's responsibility — they run the regional infra provider and subnet router that connect each region to the WireGuard mesh.

| Path | What it does |
|------|-------------|
| `clusters/` | Cluster definitions and bootstrap app-of-apps |
| `infra/omni/` | Talos machine config patches |
| `infra/ansible/` | Bootstrap playbooks |
| `apps/omni/` | Omni control plane |
| `apps/omni-infra-provider/` | PXE boot / bare-metal provisioning (gateway clusters) |

### Infrastructure (Terraform)

| Module | What it manages |
|--------|----------------|
| `infra/terraform/modules/cloudflare/` | Cloudflare DNS records and tunnels |
| `infra/terraform/modules/netbird/` | NetBird mesh, groups, DNS, and access policies (sourced from `app.yaml` `netbird:` blocks) |
| `infra/terraform/modules/mgmt_cluster/` | DigitalOcean mgmt cluster (DOKS) — co-owned with Security Platforms for cloud security review |
| `infra/terraform/modules/region/` | Regional bare-metal and cloud resources — co-owned with Security Platforms for cloud security review |

---

## Security Platforms

### Identity and SSO

Entra ID is HomeScale's identity provider. Security Platforms owns the Entra ID tenant, application registrations, and group memberships. All applications use Entra ID for SSO — while individual apps are Infrastructure Platforms's to operate, any change to an app's SSO/OIDC configuration requires Security Platforms review. See the cross-cutting concerns section below.

### Secrets management

| App | What it does |
|-----|-------------|
| `infisical` | Infisical k8s operator — syncs secrets from Infisical SaaS into cluster namespaces |

### Access control

| App | What it does |
|-----|-------------|
| `rbac` | Cluster-wide RBAC roles and bindings |

### Public cloud security

Security Platforms is responsible for the security posture of all public cloud and compute deployments (currently DigitalOcean; Azure if/when added). This means Security Platforms must review any Terraform change that provisions, modifies, or destroys cloud compute, networking, or IAM resources.

| Module | What it manages |
|--------|----------------|
| `infra/terraform/modules/mgmt_cluster/` | DigitalOcean mgmt cluster (DOKS) — co-owned with Infrastructure Platforms |
| `infra/terraform/modules/region/` | Regional cloud/bare-metal resources — co-owned with Infrastructure Platforms |

### Infrastructure (Terraform)

| Module | What it manages |
|--------|----------------|
| `infra/terraform/modules/infisical/` | Infisical project structure, machine identities, and secret path layout |
