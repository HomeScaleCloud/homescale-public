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

Deployment overrides — enabling/disabling on a specific cluster, or overriding values — are **not** set here. They live in [`clusters/<cluster>/apps.yaml`](../operations/deploying-an-app.md#deployment-overrides) instead, under an `apps:` map keyed by app directory name:

```yaml
# clusters/boa1-prod/apps.yaml, spec.sources[1].helm.values
apps:
  my-app:
    deploy: true            # overrides this app's defaultDeploy, for boa1-prod only
    values:
      someKey: clusterSpecificValue   # deep-merged over the base app.yaml, for boa1-prod only
```

See [Deployment overrides](../operations/deploying-an-app.md#deployment-overrides) for the full pattern.

---

### Helm / ArgoCD source config

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `releaseName` | string | app directory name | Helm release name |
| `repoURL` | string | global `repoURL` | Git repo URL; override to point at an external chart repo |
| `targetRevision` | string | global `targetRevision` (`main`) | Git ref (branch, tag, or SHA) |
| `values` | object | `{}` | Helm values passed to the chart. Supports Go template expressions `{{ .Values.cluster.name }}` and `{{ .Values.cluster.region }}` |
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
| `syncOptions` | list of strings | `["CreateNamespace=true"]` | Concatenated with the global `syncOptions` (duplicates removed). Common values: `ServerSideApply=true` |
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

---

### ArgoCD destination override

By default, apps deploy to the cluster that is running ArgoCD (determined by cluster name). These fields are rarely needed.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `destination.server` | string | `https://kubernetes.default.svc` | Override the destination API server URL |
| `destination.name` | string | current cluster name | Override the destination cluster name |
| `project` | string | `default` | ArgoCD project to assign this app to |

---

### NetBird access policy (`netbird:`)

Defines who can reach this app across the NetBird mesh. If absent, access is **denied by default**.

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

| Field | Type | Description |
|-------|------|-------------|
| `netbird.policy.rules` | list | One or more access rules. Each rule becomes a separate `netbird_policy` resource named `app-<name>` (single rule) or `app-<name>-0`, `app-<name>-1`, … (multiple rules) |
| `rules[].sources` | list of strings | Source groups that are granted access. See valid values below |
| `rules[].protocol` | string | `tcp` or `udp` |
| `rules[].ports` | list of strings | Port numbers as strings (e.g. `["80", "443"]`) |

The **destination** is always the app's own NetBird group (`app-<name>`), created automatically by Terraform for every app directory.

**Valid `sources` values:**

| Value | Who |
|-------|-----|
| `team-infra-plat` | Infrastructure platform team |
| `team-sec-plat` | Security platform team |
| `github-actions` | CI/CD runners |
| `owners` | Owners group (personal/family access) |
| `sg-k8s-admin` | Kubernetes admins |
| `all` | Everyone on the NetBird mesh |
| `app:<name>` | Another app's NetBird group (colon-separated, e.g. `app:metrics`) |

---

### NetBird private DNS (`netbird.cname:`)

!!! warning "Terraform input — not Helm config"
    The `netbird.cname:` block is read directly by Terraform (`infra/terraform/modules/netbird/`). It creates a per-app `netbird_dns_zone` and one `netbird_dns_record` per entry. Never delete it thinking it's dead config.

Gives an app a pretty private DNS name on the NetBird mesh, aliasing to its auto-registered `<service>.<namespace>.<cluster>REDACTED` address. The first `netbird.cname` entry for an app causes Terraform to create a dedicated zone named `<app-name>REDACTED`; every entry's `fqdn` must be a subdomain of that zone.

```yaml
netbird:
  cname:
    - fqdn: REDACTED   # must be a subdomain of <app-name>REDACTED
      cluster: boa1-prod                    # which cluster's k8s Service to alias
      service: myapp                        # optional, defaults to releaseName (falls back to app dir name)
```

| Field | Type | Description |
|-------|------|-------------|
| `cname` | list | One or more private DNS aliases for this app |
| `cname[].fqdn` | string | Private hostname; must be a subdomain of the app's auto-created `<app-name>REDACTED` zone |
| `cname[].cluster` | string | Cluster whose `<service>.<namespace>.<cluster>REDACTED` address this record points to |
| `cname[].service` | string | Optional. Kubernetes Service name to alias. Defaults to `releaseName` (or the app directory name) |

!!! note "No port field"
    A NetBird CNAME is a plain DNS alias, not a reverse proxy — it doesn't translate ports the way `exposePublic`'s Cloudflare tunnel does. Callers still connect on the target service's actual port.

Requires a matching [`netbird.policy`](#netbird-access-policy-netbird) rule to actually grant access — the DNS record alone doesn't open the mesh.

!!! warning "Avoid zone-name collisions"
    An app name that collides with an existing NetBird DNS zone (a cluster name like `boa1-prod`, or `metrics`) will conflict with that zone at `apply` time. Pick app names that don't shadow existing zones.

---

### Public exposure (`exposePublic:`)

!!! warning "Terraform input — not Helm config"
    The `exposePublic:` block is read directly by Terraform (`infra/terraform/modules/cloudflare/`). It creates a Cloudflare tunnel ingress rule and a DNS record per entry. Never delete it thinking it's dead config.

Exposes one or more Kubernetes Services to the public internet via a Cloudflare Zero Trust Tunnel. See [External service exposure](networking.md#external-service-exposure) for how it works.

```yaml
exposePublic:
  - cluster: boa1-prod   # which cluster's Cloudflare tunnel to route through
    fqdn: myapp.io        # public hostname (must be in a Cloudflare zone in the HomeScale account)
    port: 80              # backend service port
    service: myapp        # optional, defaults to releaseName (falls back to app dir name)
```

`exposePublic` is a list — add multiple entries to expose more than one Service/port/fqdn (even against different clusters) from the same app.

| Field | Type | Description |
|-------|------|-------------|
| `cluster` | string | The cluster whose Cloudflare tunnel this entry is routed through |
| `fqdn` | string | Public fully-qualified domain name. Must be globally unique across all apps. The apex zone must be a Cloudflare-managed zone |
| `port` | int | Port on the Kubernetes Service that receives traffic |
| `service` | string | Optional. Kubernetes Service name (`<service>.<namespace>.svc.cluster.local:<port>`) to route to. Defaults to `releaseName` (or the app directory name) |

---

### Using CNAME lists in your chart (`.Values.homescale`)

Unlike the rest of `exposePublic:`/`netbird:`, the flattened list of FQDNs from both blocks *is* forwarded into the chart as regular Helm values — `apps/templates/applications.yaml` computes it from the app's own `app.yaml` (before any per-cluster override) and injects it for every app, so a chart can reference its own hostnames without hardcoding them (e.g. as `Certificate` `dnsNames`):

```yaml
.Values.homescale.exposePublicFqdns   # list of strings, from this app's exposePublic[].fqdn
.Values.homescale.netbirdCnameFqdns   # list of strings, from this app's netbird.cname[].fqdn
```

Both are always present (as empty lists if the app has no entries). A chart template consuming them should still guard against being rendered standalone (e.g. via `helm template apps/<name> apps/<name>/`, which doesn't go through `apps/templates/applications.yaml` and so never sets `.Values.homescale`):

```yaml
{{- $homescale := default (dict) .Values.homescale }}
dnsNames:
{{- range (default (list) $homescale.exposePublicFqdns) }}
  - {{ . }}
{{- end }}
{{- range (default (list) $homescale.netbirdCnameFqdns) }}
  - {{ . }}
{{- end }}
```

See `apps/omni/templates/certificate.yaml` for a real example, including keeping old hostnames around as a static fallback SAN when renaming.

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

netbird:
  policy:
    rules:
      - sources: ["team-infra-plat"]
        protocol: tcp
        ports: ["443"]
  cname:
    - fqdn: REDACTED
      cluster: boa1-prod

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
helm template apps/<app-name> apps/<app-name>/

# Render the full app catalog for a cluster
helm template apps -f apps/values.yaml --set cluster.name=mgmt
```
