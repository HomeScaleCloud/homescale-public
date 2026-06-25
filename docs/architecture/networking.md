# Networking

[NetBird](https://netbird.io/) is the zero-trust WireGuard mesh that connects all humans, machines, and services in HomeScale. This page covers how services are exposed — internally to the mesh and externally to the internet.

## Human and machine access

NetBird is used for:

- **Developer access** — team members connect their laptops to the mesh and can reach internal services directly
- **CI connectivity** — GitHub Actions jobs join the mesh with an ephemeral setup key at the start of each workflow run. The key is single-use and is revoked when the job completes
- **Service exposure** — internal services are registered into the mesh and reachable at stable DNS names

NetBird policies (who can reach what) are managed in Terraform via the `netbird:` block in each `app.yaml`. See [Access policies](#netbird-access-policies) below.

## Internal service exposure

The `netbird-crs` app (syncWave -10) deploys a `NetworkRouter` CRD per cluster. The NetBird operator automatically registers each Kubernetes `Service` as a `NetworkResource` in the cluster's DNS zone. Any service is then reachable across the mesh at:

```
<service-name>.<namespace>.<cluster>xxx
```

For example, the ArgoCD server on `mgmt` is reachable at:

```
xxx
```

No Ingress or LoadBalancer service is needed — the NetBird operator handles DNS registration automatically when a `NetworkResource` CR exists.

## External service exposure

Two separate mechanisms exist for making services reachable outside the NetBird mesh.

### NetBird reverse proxy (`xxx`)

Terraform registers `xxx` as a NetBird reverse proxy domain (`netbird_reverse_proxy_domain`), and a Cloudflare wildcard CNAME resolves `xxx` to the NetBird reverse proxy cluster.

Any service already registered in the NetBird mesh at `xxx` is automatically reachable at the corresponding `xxx` address — no per-app config required.

```
Internet → Cloudflare (xxx) → NetBird reverse proxy → xxx
```

### Cloudflare Zero Trust Tunnels (`exposePublic:`)

For apps that need a specific public FQDN (e.g. `xxx`, `myapp.example.com`), add an `exposePublic:` block to the app's `app.yaml`:

```yaml
exposePublic:
  cluster: boa1-prod   # which cluster's tunnel to route through
  fqdn: myapp.io       # public hostname (must be in a Cloudflare zone Terraform manages)
  port: 80             # backend service port
```

Terraform creates:
- A `cloudflare_zero_trust_tunnel_cloudflared` resource for each cluster that has public apps (one tunnel per cluster, shared across all apps on that cluster)
- A `cloudflare_zero_trust_tunnel_cloudflared_config` ingress entry for the app pointing at `<releaseName>.<namespace>.svc.cluster.local:<port>`
- A proxied Cloudflare CNAME record for the FQDN pointing to `<tunnel-id>.cfargotunnel.com`

The `cloudflared` app (deployed on the target cluster) maintains the outbound tunnel connection to Cloudflare. Traffic flows:

```
Internet → Cloudflare (proxied CNAME) → Cloudflare Tunnel → cloudflared pod → k8s Service
```

See the [App reference](../operations/apps.md#public-exposure-exposepublic) for the full `exposePublic:` field reference.

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
- **Region ↔ mgmt connectivity** — bridges region-local services (accessible at `xxx`) to the `mgmt` cluster and vice versa

Naming convention: `<region>-gw` (e.g. `boa1-gw`).
