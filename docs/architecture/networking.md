# Networking

HomeScale uses two separate WireGuard-based networks for different purposes:

| Network | Tool | Purpose |
|---------|------|---------|
| Node-to-node | [Talos KubeSpan](https://www.talos.dev/latest/talos-guides/network/kubespan/) | Pod/service traffic across cluster nodes in different regions |
| Human and machine | [NetBird](https://netbird.io/) | Developer access, CI connectivity, service exposure |

## Node-to-node connectivity (KubeSpan)

[Talos KubeSpan](https://www.talos.dev/latest/talos-guides/network/kubespan/) automatically establishes WireGuard tunnels between **all cluster nodes** across regions. This lets pod-to-pod and service traffic flow transparently between, for example, `mgmt` and `boa1-prod` without any manual VPN configuration.

KubeSpan is configured at the Talos machine level in `infra/omni/patches/` and is enabled for all clusters.

## Human and machine access (NetBird)

[NetBird](https://netbird.io/) is a zero-trust WireGuard mesh overlay. It is used for:

- **Developer access** — team members connect their laptops to the mesh and can reach internal services directly
- **CI connectivity** — GitHub Actions jobs join the mesh with an ephemeral setup key at the start of each workflow run. The key is single-use and is revoked when the job completes
- **Service exposure** — internal services are registered into the mesh and reachable at stable DNS names

NetBird policies (who can reach what) are managed in Terraform via the `netbird:` block in each `app.yaml`. See [Access policies](#netbird-access-policies) below.

## Internal service exposure

The `netbird-crs` app (syncWave -10) deploys a `NetworkRouter` CRD per cluster. The NetBird operator automatically registers each Kubernetes `Service` as a `NetworkResource` in the cluster's DNS zone. Any service is then reachable across the mesh at:

```
<service-name>.<namespace>.<cluster>REDACTED
```

For example, the ArgoCD server on `mgmt` is reachable at:

```
REDACTED
```

No Ingress or LoadBalancer service is needed — the NetBird operator handles DNS registration automatically when a `NetworkResource` CR exists.

## External service exposure

Public internet exposure uses a two-step Terraform-managed pattern:

```
Internet → Cloudflare (DNS + proxy) → NetBird reverse proxy → internal REDACTED service
```

1. A **NetBird reverse proxy** resource is created in Terraform, pointing at the internal `REDACTED` FQDN. This gives the service an address under `REDACTED` (the reverse proxy domain registered in `netbird.tf`).
2. A **Cloudflare wildcard CNAME** (`REDACTED`) resolves to the NetBird reverse proxy cluster. Optionally a second CNAME maps a friendlier public hostname (e.g. `myapp.example.com`) to the same target.

This pattern is driven by the `exposePublic:` block in `app.yaml` — see the [App reference](../operations/apps.md#public-exposure-exposepublic) for details.

Alternatively, apps can use **Cloudflare Tunnel** (`cloudflared` app) for direct zero-trust ingress without a reverse proxy hop. This is configured via the same `exposePublic:` block with `cluster` pointing at the cluster running the `cloudflared` app.

## NetBird access policies

Each `apps/<name>/app.yaml` may include a top-level `netbird:` block. This is **not a Helm value** — it is read directly by Terraform (`infra/terraform/modules/netbird/policies.tf`) to create [`netbird_policy`](https://registry.terraform.io/providers/netbirdio/netbird/latest/docs/resources/policy) resources.

!!! warning "Never delete a `netbird:` block thinking it's dead config"
    It has no visible effect on Helm rendering but drives real infrastructure. Removing it removes network access for that app.

```yaml
netbird:
  policy:
    rules:
      - sources: ["team-infra-plat", "app:other-app"]
        protocol: tcp
        ports: ["443", "9090"]
      - sources: ["all"]
        protocol: udp
        ports: ["25565"]
```

The **destination** is always the app's own NetBird group (`app-<name>`), created automatically by Terraform for every app directory that exists. If no `netbird:` block is present, **access is denied by default**.

Multiple rules under `policy.rules` produce separate `netbird_policy` resources named `app-<name>-0`, `app-<name>-1`, etc.

### Valid `sources` values

| Value | Who |
|-------|-----|
| `team-infra-plat` | Infrastructure platform team |
| `team-sec-plat` | Security platform team |
| `github-actions` | CI/CD runners |
| `owners` | Owners group (personal / family access) |
| `sg-k8s-admin` | Kubernetes admins security group |
| `all` | Everyone on the NetBird mesh |
| `app:<name>` | Another app's NetBird group (colon-separated, e.g. `app:metrics`) |

## Gateway clusters

Gateway clusters (`<region>-gw`) are single-node clusters — one per region — that handle bare-metal provisioning and act as the regional entry point into the HomeScale mesh:

- **Bare-metal provisioning** — runs [`omni-infra-provider`](https://omni.siderolabs.com/how-to-guides/install-and-configure-omni-integration-in-bare-metal-mode) to PXE-boot Talos nodes in the region
- **Subnet routing** — runs a NetBird subnet router that exposes the region's BMC and MGMT subnets (switch management, iDRAC/IPMI, etc.) across the WireGuard mesh
- **Region ↔ mgmt connectivity** — bridges region-local services (accessible at `REDACTED`) to the `mgmt` cluster and vice versa

Naming convention: `<region>-gw` (e.g. `boa1-gw`).
