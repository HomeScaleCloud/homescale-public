# Networking

[Tailscale](https://tailscale.com/) is the zero-trust mesh that connects all humans, machines, and services in HomeScale. This page covers how services are exposed — internally to the tailnet and externally to the internet.

## Human and machine access

Tailscale is used for:

- **Developer access** — team members connect their devices to the tailnet and can reach internal services directly
- **CI connectivity** — GitHub Actions jobs that need to reach internal infrastructure (Omni) join the tailnet as an ephemeral node via `tailscale/github-action`, tagged `tag:github-actions` and automatically removed when the job completes
- **Service exposure** — internal services are exposed to the tailnet via the Tailscale Kubernetes Operator and reachable at stable DNS names

Human/team access is granted via Entra ID groups, SCIM-synced into Tailscale — see [Access policies](#access-policies) below.

## Internal service exposure

The `tailscale` app deploys the official Tailscale Kubernetes Operator to every cluster, along with a shared per-cluster ingress `ProxyGroup`. A Service opts into tailnet exposure with:

```yaml
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
```

annotated:

```yaml
metadata:
  annotations:
    tailscale.com/tags: "tag:k8s,tag:app-myapp,tag:cluster-{{ .Values.cluster.name }}"
    tailscale.com/hostname: "myapp-{{ .Values.cluster.name }}"
    tailscale.com/proxy-group: ingress
    external-dns.alpha.kubernetes.io/hostname: "myapp.{{ .Values.cluster.name }}REDACTED"
```

`tailscale.com/proxy-group: ingress` routes the Service through the cluster's shared ingress `ProxyGroup` instead of provisioning a dedicated proxy pod per Service. `external-dns` (running in every cluster) publishes the `external-dns.alpha.kubernetes.io/hostname` value as a CNAME in Cloudflare, pointing at whatever `<hostname>.<tailnet>.ts.net` address the Operator assigns the proxy. For example, the ArgoCD server on the management cluster is reachable at:

```
REDACTED
```

Pods that need *outbound* access to tailnet-only targets (rather than being reached) use an `ExternalName` Service annotated `tailscale.com/tailnet-fqdn` — pointing at the target's own tailnet hostname — instead of `loadBalancerClass`/`tailscale.com/proxy-group`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-egress
  annotations:
    tailscale.com/tailnet-fqdn: "target-app-othercluster.{{ .Values.tailscale.tailnet }}"
    tailscale.com/tags: "tag:k8s,tag:app-myapp,tag:cluster-{{ .Values.cluster.name }}"
    tailscale.com/hostname: "myapp-{{ .Values.cluster.name }}-egress"
spec:
  type: ExternalName
  externalName: placeholder
  ports:
    - port: 443
```

With no `tailscale.com/proxy-group` annotation, the Operator provisions a dedicated proxy `StatefulSet` for this one Service (not routed through the shared `ingress` `ProxyGroup`), which is what makes `tailscale.com/tags` meaningful here: a `ProxyGroup` registers its member proxies under its own fixed `tags:` regardless of what any individual Service requests, but a dedicated per-Service proxy takes the Service's own `tailscale.com/tags` annotation as its identity — so it's authorized by the same ACL `app_grants` rule as everything else that app owns, with no separate egress-specific policy needed. `tailscale.com/hostname` is optional but keeps the resulting device identifiable in the tailnet admin console instead of an auto-generated name.

### Direct cluster API access

Each cluster's kube-apiserver is reachable, via a small TLS-terminating reverse proxy, at:

```
k8s.api.<cluster>REDACTED
```

`tailscale` runs this proxy (`kube-apiserver-proxy`, an `nginx` Deployment in the `tailscale` namespace) rather than exposing the cluster's built-in `kubernetes` Service directly, since the built-in Service is backed by `hostNetwork` apiserver pods rather than a normal selector-based ClusterIP. The proxy is a normal ClusterIP Service in front of it, forwarding to `kubernetes.default.svc.cluster.local` — the same in-cluster address every pod already uses, which Kubernetes itself load-balances across every control-plane replica. It terminates TLS with a real cert-manager/LetsEncrypt certificate (`apps/tailscale/templates/certificate-apiserver-proxy.yaml`, same `letsencrypt` `ClusterIssuer` Headlamp's own cert uses) rather than the cluster's internal CA, so clients get standard, publicly-trusted TLS verification — no `insecure-skip-tls-verify`, no CA to distribute. Whatever auth the client presents (e.g. a forwarded per-user OIDC bearer token) passes straight through in the `Authorization` header; the real apiserver still does the actual authn/authz.

`hsctl get kubeconfig`/`hsctl switch` default to this direct path (`kubectl-oidc_login` handles the OIDC login, PKCE, no client secret); `--omni`/`--break-glass` delegate straight to `omnictl kubeconfig` (see [`hsctl` reference](../operations/hsctl.md)).

Headlamp shows `boa1-prod` in its cluster picker via this same direct path, with the same per-user RBAC it already has for `mgmt`. Which clusters appear is derived automatically — Terraform (`infra/terraform/headlamp.tf`) scans `clusters/*/cluster.yaml` for ones referencing `infra/omni/patches/oidc.yaml` and publishes the list to Infisical, which `apps/headlamp/templates/kubeconfig-secret.yaml` renders into a kubeconfig context per cluster. Adding a cluster to Headlamp's picker is then just adding the OIDC patch to its `cluster.yaml` — no separate list to maintain.

## External service exposure

Public internet exposure goes through Cloudflare Zero Trust Tunnels — entirely independent of Tailscale. Add an `exposePublic:` block to the app's `app.yaml` — it's a list, so one app can expose multiple Services/ports/fqdns:

```yaml
exposePublic:
  - cluster: boa1-prod   # which cluster's tunnel to route through
    fqdn: myapp.io        # public hostname (must be in a Cloudflare zone in the HomeScale account)
    port: 80              # backend service port
    service: myapp        # optional, defaults to releaseName
```

Terraform creates:
- A `cloudflare_zero_trust_tunnel_cloudflared` resource for each cluster that has public apps (one tunnel per cluster, shared across all apps on that cluster)
- A `cloudflare_zero_trust_tunnel_cloudflared_config` ingress entry for each entry, pointing at `<service>.<namespace>.svc.cluster.local:<port>` (`https://` instead of `http://` when `tls: true`)
- A proxied Cloudflare CNAME record for each entry's FQDN pointing to `<tunnel-id>.cfargotunnel.com`

The `cloudflared` app (deployed on the target cluster) maintains the outbound tunnel connection to Cloudflare. Traffic flows:

```
Internet → Cloudflare (proxied CNAME) → Cloudflare Tunnel → cloudflared pod → k8s Service
```

See the [App reference](apps.md#public-exposure-exposepublic) for the full `exposePublic:` field reference.

### Gating a public app behind Cloudflare Access

Add an `access:` block to an `exposePublic:` entry to require Entra ID (or whichever identity providers are configured in the Cloudflare Zero Trust account) login before traffic reaches the tunnel — enforced at Cloudflare's edge, in front of the proxied DNS record:

```yaml
exposePublic:
  - cluster: mgmt
    fqdn: REDACTED
    port: 443
    tls: true
    access:
      allowedIdps: []       # optional — omit to allow any IdP configured in the account
      sessionDuration: "24h" # optional
```

Terraform (`infra/terraform/modules/cloudflare/access.tf`) creates a `cloudflare_zero_trust_access_application` for the FQDN with a single "allow everyone" policy — i.e. any user who authenticates via an allowed identity provider is granted access, with no group or email restriction. Restricting to specific groups isn't implemented — extend the module's `policies` block if that's ever needed. See the [App reference](apps.md#public-exposure-exposepublic) for the full `access:` field reference.

## Access policies

Each `apps/<name>/app.yaml` may include a top-level `tailscale:` block. This is **not a Helm value** — it is read directly by Terraform (`infra/terraform/modules/tailscale/acl.tf`) via `fileset`/`yamldecode` and flattened, along with every other app's rules, into a single [`tailscale_acl`](https://registry.terraform.io/providers/tailscale/tailscale/latest/docs/resources/acl) resource (Tailscale's ACL model is one policy document, not many discrete objects).

!!! warning "Never delete a `tailscale:` block thinking it's dead config"
    It has no visible effect on Helm rendering but drives real infrastructure. Removing it removes network access for that app.

```yaml
tailscale:
  policy:
    rules:
      - sources: ["group:team-infra-plat@REDACTED", "app:other-app"]
        protocol: tcp
        ports: ["443", "9090"]
      - sources: ["*"]
        protocol: udp
        ports: ["25565"]
```

The **destination** is always the app's own tag (`tag:app-<name>`), auto-registered in `tagOwners` by Terraform for every app directory. If no `tailscale:` block is present, **access is denied by default**. `sources` values are literal ACL identifiers, spelled out in full (`group:<name>@REDACTED` for Entra-synced groups, `tag:<name>` for tags, `*` for everyone) — there's no short-alias remapping.

See the [App reference](apps.md#tailscale-access-policy-tailscale) for the full field reference.
