# Apps

Each app lives in `apps/<name>/` and is controlled by an `app.yaml`. The app catalog Helm chart (`apps/`) reads every `apps/*/app.yaml` and generates one ArgoCD `Application` per enabled app per cluster.

Apps with both a `Chart.yaml` and a `Dockerfile` under `apps/<name>/` are built and pushed to `ghcr.io/homescalecloud/<name>` by CI on every merge to `main`.

---

## `app.yaml` field reference

### Required fields

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Path to the Helm chart directory (e.g. `apps/my-app`) |
| `namespace` | string | Kubernetes namespace the app deploys into |

---

### Deployment control

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `defaultDeploy` | bool | `false` | Deploy to every cluster unless overridden |

Deployment overrides — enabling/disabling on a specific cluster, or overriding any other field — are **not** set here. They live in [`clusters/<cluster>/apps.yaml`](../operations/deploying-an-app.md#deployment-overrides) instead, under an `apps:` map keyed by app directory name. The override object is merged directly onto the entire base `app.yaml`, so any top-level key (`values`, `syncWave`, `podSecurity`, `tailscale`, `exposePublic`, `ignoreDifferences`, ...) can be overridden per cluster, not just `deploy`/`values`:

```yaml
# clusters/boa1-prod/apps.yaml, spec.sources[1].helm.values
apps:
  my-app:
    deploy: true            # overrides this app's defaultDeploy, for boa1-prod only
    syncWave: 5              # any other top-level app.yaml field also merges, for boa1-prod only
    values:
      someKey: clusterSpecificValue   # deep-merged over the base app.yaml, for boa1-prod only
```

The merge is a deep merge on maps, but **lists are replaced wholesale, not concatenated** — overriding `values.someList: [z]` replaces a base `[a, b]` entirely rather than appending to it. This matters for list-valued fields like `ignoreDifferences` or `tailscale.policy.rules`.

See [Deployment overrides](../operations/deploying-an-app.md#deployment-overrides) for the full pattern.

---

### Helm / ArgoCD source config

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `releaseName` | string | app directory name | Helm release name |
| `repoURL` | string | global `repoURL` | Git repo URL; override to point at an external chart repo |
| `targetRevision` | string | global `targetRevision` (`main`) | Git ref (branch, tag, or SHA) |
| `values` | object | `{}` | Helm values passed to the chart. The whole object is rendered through Helm's `tpl`, so any Go template expression resolvable against the chart's root context works — not just `{{ .Values.cluster.name }}`, though that's the common case (`.Values.cluster.region` is also plumbed through from `apps/values.yaml` but isn't read by any shipped app today). `annotations` and `ignoreDifferences` get the same `tpl` treatment |
| `valueFiles` | list of strings | — | Additional Helm value files to load (paths relative to the chart) |
| `extraSources` | list of ArgoCD sources | — | Adds extra source entries to the ArgoCD Application, switching it to multi-source mode. The app's own chart is always the first source |

**Example — `extraSources` for a chart that needs a second repo:**
```yaml
extraSources:
  - repoURL: https://charts.example.com
    chart: some-chart
    targetRevision: 1.2.3
```

---

### Sync behavior

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `syncWave` | int | `0` | ArgoCD sync wave. Lower numbers sync first. See [sync wave order](overview.md#sync-wave-order) |
| `syncPolicy` | object | global automated prune+self-heal | Merged over the global `syncPolicy`. Use to disable automated sync or self-heal for a specific app |
| `syncOptions` | list of strings | `["CreateNamespace=true", "SkipDryRunOnMissingResource=true"]` | Concatenated with the global `syncOptions` (duplicates removed). Common values: `ServerSideApply=true` |
| `ignoreDifferences` | list | — | ArgoCD `ignoreDifferences` entries — suppress spurious drift detection on fields that are mutated out-of-band (e.g. webhook CABundles, generated secrets) |
| `annotations` | object | — | Extra annotations added to the ArgoCD `Application` resource itself (not to app workloads) |

**Example — ignore a webhook CA bundle that gets rewritten by cert-manager:**
```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    name: my-webhook
    jsonPointers:
      - /webhooks
```

**Example — disable automated sync for a specific app:**
```yaml
syncPolicy:
  automated: null
```

---

### Namespace config

| Field | Type | Description |
|-------|------|-------------|
| `podSecurity` | string | Applies Kubernetes [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) labels to the namespace. Valid values: `privileged`, `baseline`, `restricted` |

When set, the namespace gets `pod-security.kubernetes.io/enforce`, `/warn`, and `/audit` labels all set to the chosen level.

!!! note "Namespace objects are auto-generated, one per distinct namespace"
    The catalog chart creates a `Namespace` resource for every distinct `namespace` value across all `app.yaml` files (skipping the hardcoded system namespaces `argocd`, `kube-system`, `kube-public`, `kube-node-lease`, `default`). If multiple apps share a namespace, only the first one processed (by file glob order) contributes its `podSecurity` labels. Every generated `Namespace` carries a hardcoded `argocd.argoproj.io/sync-wave: "-35"` annotation regardless of the owning app's own `syncWave`, so the namespace exists before anything else in that namespace tries to sync.

---

### ArgoCD destination override

By default, `destination.server` resolves to `https://kubernetes.default.svc` (the in-cluster API server) for every app, via the global default in `apps/values.yaml` — so in practice every Application deploys to the cluster running ArgoCD. `destination.name` (deploying by cluster name rather than server URL) is only used if `destination.server` is explicitly cleared; no app or cluster does this today. These fields are rarely needed.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `destination.server` | string | `https://kubernetes.default.svc` | Override the destination API server URL |
| `destination.name` | string | current cluster name | Override the destination cluster name |
| `project` | string | `default` | ArgoCD project to assign this app to |

---

### Tailscale access policy (`tailscale:`)

Defines who can reach this app over the tailnet. If absent, access is **denied by default**.

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

| Field | Type | Description |
|-------|------|-------------|
| `tailscale.policy.rules` | list | One or more access rules. All apps' rules are flattened into a single `tailscale_acl` resource (Tailscale's ACL is one policy document, not many discrete objects) |
| `rules[].sources` | list of strings | Source identifiers granted access — always the literal ACL value, not a short alias (see below) |
| `rules[].protocol` | string | `tcp` or `udp` |
| `rules[].ports` | list of strings | Port numbers as strings (e.g. `["80", "443"]`) |

The **destination** is always the app's own tag (`tag:app-<name>`), auto-registered in `tagOwners` by Terraform for every app directory.

**`sources` values are literal ACL identifiers, spelled out in full — there's no short-alias remapping:**

| Value | Who |
|-------|-----|
| `group:<name>@REDACTED` | An Entra ID group, SCIM-synced into Tailscale (e.g. `group:team-infra-plat@REDACTED`, `group:owners@REDACTED`) |
| `tag:github-actions` | CI/CD runners |
| `tag:app-<name>` | Another app's own tag (e.g. `tag:app-metrics`) |
| `*` | Everyone on the tailnet |

---

### Exposing a Service on the tailnet

Unlike NetBird, Tailscale doesn't auto-register a Service once a `tailscale:` policy exists — you also mark the Service itself for exposure:

```yaml
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
```

with annotations giving it a tailnet identity and (optionally) a friendly internal DNS name:

```yaml
metadata:
  annotations:
    tailscale.com/tags: "tag:k8s,tag:app-myapp,tag:cluster-{{ .Values.cluster.name }}"
    tailscale.com/hostname: "myapp-{{ .Values.cluster.name }}"
    tailscale.com/proxy-group: ingress
    external-dns.alpha.kubernetes.io/hostname: "myapp.{{ .Values.cluster.name }}REDACTED"
```

| Annotation | Description |
|------------|-------------|
| `tailscale.com/tags` | Tags applied to the tailnet device for this Service. Always include `tag:k8s` and `tag:app-<name>`; add `tag:cluster-<name>` for anything cluster-scoped |
| `tailscale.com/hostname` | The MagicDNS label for this device (`<hostname>.<tailnet>.ts.net`) |
| `tailscale.com/proxy-group` | Set to `ingress` to route through the cluster's shared ingress `ProxyGroup` (from the `tailscale` app) instead of provisioning a dedicated proxy pod |
| `external-dns.alpha.kubernetes.io/hostname` | Optional. Publishes a friendly `REDACTED` CNAME (via `external-dns`, running in every cluster) pointing at whatever tailnet hostname the Operator assigns — this replaces NetBird's `netbird.cname:` block entirely, no separate Terraform-managed DNS zone involved |

Requires a matching [`tailscale.policy`](#tailscale-access-policy-tailscale) rule to actually grant access — exposing the Service alone doesn't open the tailnet.

---

### Public exposure (`exposePublic:`)

!!! warning "Mostly a Terraform input, not Helm config"
    Terraform (`infra/terraform/modules/cloudflare/`) reads this block directly to create a Cloudflare tunnel ingress rule and a DNS record per entry — that's its real purpose. Never delete it thinking it's dead config. One caveat: the app catalog chart *does* read each entry's `fqdn` (only) to populate `.Values.homescale.exposePublicFqdns` — see [below](#using-cname-lists-in-your-chart-valueshomescale).

Exposes one or more Kubernetes Services to the public internet via a Cloudflare Zero Trust Tunnel. See [External service exposure](networking.md#external-service-exposure) for how it works.

```yaml
exposePublic:
  - cluster: boa1-prod   # which cluster's Cloudflare tunnel to route through
    fqdn: myapp.io        # public hostname (must be in a Cloudflare zone in the HomeScale account)
    port: 80              # backend service port
    service: myapp        # optional, defaults to releaseName (falls back to app dir name)
    tls: false             # optional, defaults to false — set true if the backend Service only speaks TLS
    cacheBypass: false     # optional, defaults to false — set true to bypass Cloudflare's edge cache entirely for this hostname
    access:                # optional — omit entirely to leave the hostname open to the internet
      allowedIdps: []       # optional, list of Cloudflare Zero Trust identity provider names; defaults to every IdP configured in the account
      sessionDuration: "24h" # optional, defaults to Cloudflare's own default (24h)
```

`exposePublic` is a list — add multiple entries to expose more than one Service/port/fqdn (even against different clusters) from the same app.

| Field | Type | Description |
|-------|------|-------------|
| `cluster` | string | The cluster whose Cloudflare tunnel this entry is routed through |
| `fqdn` | string | Public fully-qualified domain name. Must be globally unique across all apps. The apex zone must be a Cloudflare-managed zone |
| `port` | int | Port on the Kubernetes Service that receives traffic |
| `service` | string | Optional. Kubernetes Service name (`<service>.<namespace>.svc.cluster.local:<port>`) to route to. Defaults to `releaseName` (or the app directory name) |
| `tls` | bool | Optional, defaults to `false`. Set `true` if the backend Service only accepts TLS (`http://` otherwise). cloudflared verifies the origin certificate against `fqdn` as the expected server name — the app's own `Certificate` must include `fqdn` in `dnsNames` (add `.Values.homescale.exposePublicFqdns` there, see [below](#using-cname-lists-in-your-chart-valueshomescale)) |
| `cacheBypass` | bool | Optional, defaults to `false`. Set `true` to create a Cloudflare Cache Rule that bypasses the edge cache for every request to this hostname — use for live/dynamic apps (dashboards, APIs) where a stale cached response would be wrong, as opposed to static sites that benefit from CDN caching |
| `access` | object | Optional. Gates this hostname behind [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/) — omit entirely to leave it open to the internet. Any authenticated user is allowed through (no group/email restriction) once they pass one of the allowed identity providers |
| `access.allowedIdps` | list of strings | Optional. Identity provider names (as configured in the Cloudflare Zero Trust dashboard) users may authenticate with. Omit to allow any IdP configured in the account (today: Entra ID only) |
| `access.sessionDuration` | string | Optional. How long an Access session lasts before re-authentication, e.g. `24h`. Defaults to Cloudflare's own default |

---

### Using exposePublic FQDNs in your chart (`.Values.homescale`)

Unlike `tailscale:`, the flattened list of FQDNs from `exposePublic:` *is* forwarded into the chart as a regular Helm value — `apps/templates/applications.yaml` computes it from the app's own `app.yaml` (before any per-cluster override) and injects it for every app, so a chart can reference its own public hostnames without hardcoding them (e.g. as `Certificate` `dnsNames`):

```yaml
.Values.homescale.exposePublicFqdns   # list of strings, from this app's exposePublic[].fqdn
```

Always present (as an empty list if the app has no entries). A chart template consuming it should still guard against being rendered standalone (e.g. via `helm template <name> apps/<name>/`, which doesn't go through `apps/templates/applications.yaml` and so never sets `.Values.homescale`):

```yaml
{{- $homescale := default (dict) .Values.homescale }}
dnsNames:
{{- range (default (list) $homescale.exposePublicFqdns) }}
  - {{ . }}
{{- end }}
```

Tailscale-side internal hostnames don't go through this mechanism — a Service's `external-dns.alpha.kubernetes.io/hostname` annotation (see [Exposing a Service on the tailnet](#exposing-a-service-on-the-tailnet)) is what actually publishes the DNS record, so a chart's `Certificate` `dnsNames` should list those hostnames directly rather than reading them from `.Values.homescale`. See `apps/omni/templates/certificate.yaml` for a real example, including keeping old hostnames around as a static fallback SAN when renaming.

---

## Sync wave order

See [sync wave order](overview.md#sync-wave-order) in the architecture overview.

---

## Full example

```yaml
path: apps/my-app
namespace: my-app
releaseName: my-app            # optional, defaults to directory name
syncWave: 0
podSecurity: restricted
defaultDeploy: false

syncOptions:
  - ServerSideApply=true

ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    name: my-app-webhook
    jsonPointers:
      - /webhooks

tailscale:
  policy:
    rules:
      - sources: ["group:team-infra-plat@REDACTED"]
        protocol: tcp
        ports: ["443"]

exposePublic:
  - cluster: boa1-prod
    fqdn: myapp.example.com
    port: 80

values:
  cluster:
    name: "{{ .Values.cluster.name }}"
  image:
    tag: "1.2.3"
```

Deployment overrides for `my-app` go in `clusters/<cluster>/apps.yaml` instead — see [Deployment overrides](../operations/deploying-an-app.md#deployment-overrides).

---

## Linting

```bash
# Render a specific app chart
helm template <app-name> apps/<app-name>/

# Render the full app catalog for a cluster
helm template apps -f apps/values.yaml --set cluster.name=mgmt
```
