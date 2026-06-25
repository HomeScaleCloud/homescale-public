# Networking

## Node-to-node (KubeSpan)

Talos KubeSpan automatically establishes WireGuard tunnels between all cluster nodes across regions.

## Human and machine access (NetBird)

NetBird is a zero-trust WireGuard mesh used for human/machine access and service exposure. CI jobs join the mesh with an ephemeral setup key generated at the start of each workflow run and revoked at the end.

## Internal service exposure

The `netbird-crs` app deploys a `NetworkRouter` CRD per cluster. The NetBird operator registers each `NetworkResource` into the cluster's DNS zone, making any k8s Service reachable at:

```
<service-name>.<namespace>.<cluster>xxx
```

## External service exposure

A two-step pattern managed in Terraform:

1. A NetBird reverse proxy resource points at the internal `xxx` FQDN, giving the service an address under `xxx`.
2. A Cloudflare `xxx` wildcard CNAME resolves to the NetBird reverse proxy cluster. Optionally a second CNAME is added for a friendlier public URL.

## NetBird access policies

Each `apps/<name>/app.yaml` may include a top-level `netbird:` block (outside of `values:`). This is read directly by Terraform to create `netbird_policy` resources — it has no effect on Helm rendering.

```yaml
netbird:
  policy:
    rules:
      - sources: ["team-infra-plat", "app:myapp"]
        protocol: tcp
        ports: ["443", "9090"]
```

`destinations` is always the app's own NetBird group (`app-<app-name>`), created automatically for every app directory. Valid `sources`:

- `team-infra-plat`, `team-sec-plat`, `github-actions`, `owners`, `sg-k8s-admin`, `all`
- `app:<name>` — another app's group

If an app has no `netbird:` block, no policy is created and access is denied by default.
