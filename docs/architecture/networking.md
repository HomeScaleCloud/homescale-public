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
<service-name>.<namespace>.<cluster>REDACTED
```

For example, the ArgoCD server on the management cluster is reachable at:

```
argocd-server.argocd.<cluster>REDACTED
```

No Ingress or LoadBalancer service is needed — the NetBird operator handles DNS registration automatically when a `NetworkResource` CR exists.

## External service exposure

Public internet exposure goes through Cloudflare Zero Trust Tunnels. Add an `exposePublic:` block to the app's `app.yaml`:

```yaml
exposePublic:
  cluster: boa1-prod   # which cluster's tunnel to route through
  fqdn: myapp.io       # public hostname (must be in a Cloudflare zone in the HomeScale account)
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

See the [App reference](apps.md#public-exposure-exposepublic) for the full `exposePublic:` field reference.

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

The **destination** is always the app's own NetBird group (`app-<name>`), created automatically by Terraform for every app directory. If no `netbird:` block is present, **access is denied by default**.

See the [App reference](apps.md#netbird-access-policy-netbird) for the full field reference including valid `sources` values.

## Gateway clusters

Gateway clusters (`<region>-gw`) are single-node clusters — one per region — that handle bare-metal provisioning and act as the regional entry point into the HomeScale mesh:

- **Bare-metal provisioning** — runs [`omni-infra-provider`](https://omni.siderolabs.com/how-to-guides/install-and-configure-omni-integration-in-bare-metal-mode) to PXE-boot Talos nodes in the region
- **Subnet routing** — runs a NetBird subnet router that exposes the region's BMC and MGMT subnets (switch management, iDRAC/IPMI, etc.) across the WireGuard mesh
- **Region ↔ management connectivity** — bridges region-local services (accessible at `*.<region>REDACTED`) to the management cluster and vice versa

Naming convention: `<region>-gw`.
