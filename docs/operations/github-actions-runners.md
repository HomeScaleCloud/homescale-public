# GitHub Actions Self-Hosted Runners

CI can run on a self-hosted runner pool on `boa1-prod` instead of GitHub-hosted `ubuntu-latest` runners, using a custom image (`apps/github-runner/Dockerfile`) with dependencies pre-installed so jobs don't reinstall Terraform, Helm, Ansible, etc. on every run. If the pool is unavailable for any reason, CI transparently falls back to GitHub-hosted runners and installs dependencies as before — no workflow breaks either way.

## Architecture

Two catalog apps, deployed only to `boa1-prod`:

- **`apps/github-runner-controller`** — [Actions Runner Controller](https://github.com/actions/actions-runner-controller) (ARC), the `gha-runner-scale-set-controller` chart. One instance, cluster-wide.
- **`apps/github-runner`** — the runner pool itself, the `gha-runner-scale-set` chart, configured with our custom image and `containerMode.type: dind` (a Docker-in-Docker sidecar, needed so `docker/build-push-action` in `build.yaml` has a real daemon to talk to). Runner scale set / `runs-on` label: `homescale-runners`.

Both apps share the `github-runner` namespace — safe because they're still two separate Helm releases/ArgoCD Applications (only *merging them into one chart* hit the naming bug below), and ARC's `controllerServiceAccount` value exists precisely to let the runner scale set reference the controller's ServiceAccount across releases. One gotcha from sharing: the catalog chart only applies `podSecurity` labels from the *first* app processed for a given namespace (by file glob order — see `docs/architecture/apps.md`), so both `app.yaml`s set `podSecurity: privileged` rather than relying on only the runner app to do it.

They're **not** merged into a single chart/Application, even though `gha-runner-scale-set-controller` and `gha-runner-scale-set` could technically be declared as two dependencies of one `Chart.yaml`: both charts independently define a generically-named internal Helm template (`gha-base-name`, meaning something different in each), and Helm's `define` blocks share one global namespace across a parent chart and its subcharts — combining them silently corrupted the runner scale set's resource names with the controller's naming. Confirmed by testing it; reverted.

`minRunners` is `3`, not `0`: with autoscale-to-zero, no runner would ever be registered while idle, and CI's "is the pool available" check (below) would have nothing to observe. Warm runners keep that check meaningful, avoid cold-start delay, and let multiple jobs run in parallel without falling back to cloud runners. `maxRunners` is `6`.

The runner scale set is registered at the **org** level (`githubConfigUrl: https://github.com/HomeScaleCloud`), so any repo in `HomeScaleCloud` can use the pool, not just `homescale`.

## Setting it up

There are two, unrelated pieces of auth here — don't conflate them: the **GitHub App** is how the runner pool itself registers with GitHub (ARC's own credential, lives in the cluster); the **PAT** below is only for CI's "is the pool online" check (lives in GitHub Actions secrets, never touches the cluster). The check doesn't use the App at all.

### 1. Create a GitHub App

In the `HomeScaleCloud` org → **Settings → Developer settings → GitHub Apps → New GitHub App**:

- Repository permissions: `Actions: Read-only`, `Administration: Read & write`
- Organization permissions: `Self-hosted runners: Read & write`
- No webhook, no user authorization needed
- Generate a private key (downloads a `.pem`)
- Install the app on the org (all repositories)

### 2. Add secrets to Infisical

At `/k8s/github-runner` (prod env):

| Key | Value |
|-----|-------|
| `github_app_id` | The App ID from the app's settings page |
| `github_app_installation_id` | The installation ID (visible in the URL after installing the app on the org) |
| `github_app_private_key` | The full contents of the downloaded `.pem` |

These are synced into the `github-runner` namespace as the `github-runner-github-app` secret by `apps/github-runner/templates/secret.yaml`, and referenced by the chart's `githubConfigSecret` value.

### 3. Create a PAT for the CI availability check

Org owner → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → New token**, scoped to the `HomeScaleCloud` org, with **Organization permissions → Self-hosted runners: Read-only** and nothing else. Add it to Infisical at `/github-actions` (prod env) as `RUNNER_CHECK_TOKEN` — the same path every other CI-only secret (`TAILSCALE_OAUTH_CLIENT_ID`, `VULTR_TOKEN`, etc.) already lives at, not a raw GitHub Actions secret.

Fine-grained PATs belong to a user, so this needs periodic rotation (GitHub caps the max lifetime) and breaks if that user's org access ever changes — acceptable tradeoffs for a homelab; see [below](#auth-a-plain-pat-not-a-github-app) for why this is simpler than the alternative.

### 4. Make the runner image public

The `homescale` repo is private, so `ghcr.io/homescalecloud/github-runner` defaults to a private package on first push — which the cluster can't pull without an image pull secret. Since the image itself has no secrets baked in (just public tooling on top of the public `ghcr.io/actions/actions-runner` base), the simplest fix is to make the package public instead of managing a pull secret: after the first successful build (merge a change under `apps/github-runner/` to `main`), go to the package's settings on `github.com/orgs/HomeScaleCloud/packages` and change its visibility to public.

## How the CI fallback works

Every job in `scan.yaml`, `build.yaml`, `deploy.yaml`, and `mirror.yaml` depends on a `homescale-runners` job (`.github/workflows/homescale-runners.yaml`, itself a nested reusable workflow), which checks whether the pool has an online runner. Downstream jobs pick their `runs-on` from that result:

```yaml
runs-on: ${{ needs.homescale-runners.outputs.self_hosted == 'true' && 'homescale-runners' || 'ubuntu-latest' }}
```

Steps that install something the custom image already bakes in (Terraform, Helm, Ansible, mkdocs-material, git-filter-repo, etc.) are guarded the same way, so they only run on the GitHub-hosted fallback:

```yaml
if: needs.homescale-runners.outputs.self_hosted != 'true'
```

`claude.yml` (the `@claude` mention bot) intentionally does **not** go through this — it's not part of the build/test/deploy pipeline and has no heavy dependency-install steps to save.

### Auth: a plain PAT, not a GitHub App

The check needs to call `GET /orgs/HomeScaleCloud/actions/runners`. The automatic `GITHUB_TOKEN` **cannot call this endpoint under any circumstances** — confirmed empirically via a temporary debug run: `403 Resource not accessible by integration`, even with `actions: read` correctly granted. This is a hard GitHub restriction on the ephemeral Actions token for runner-management endpoints specifically (true at repo scope too, not just org scope) — GitHub's documented fine-grained permission model (`actions: read` suffices) describes PAT/GitHub-App-token behavior, not `GITHUB_TOKEN`'s.

An earlier version of this check authenticated as a GitHub App instead — minting a short-lived *installation* token via `actions/create-github-app-token` (on top of an Infisical import to get the App's credentials). It worked, but added a second auth layer on top of Infisical for no real benefit: an extra token-minting step, and `id-token: write` needing to be correct on every caller's permissions block. That last part bit twice — it's checked at **workflow parse time** (GitHub validates that a called reusable workflow's requested permissions are a subset of what every caller in the chain grants), so getting it wrong doesn't fail the check job, it fails the *entire run* at startup with no useful error anywhere except the run's page in the browser.

The simpler fix: skip the App/installation-token layer and use a plain fine-grained PAT (`RUNNER_CHECK_TOKEN`, see setup above), pulled from Infisical at `/github-actions` exactly like every other CI-only secret already is:

```yaml
- uses: Infisical/secrets-action@v1.0.16
  with:
    method: "oidc"
    secret-path: "/github-actions"
    export-type: env
- env:
    GH_TOKEN: ${{ env.RUNNER_CHECK_TOKEN }}
  run: gh api "/orgs/HomeScaleCloud/actions/runners" ...
```

`secrets: inherit` on every `homescale-runners:` job call (in `ci.yaml` and in each reusable workflow) threads `INFISICAL_GH_IDENTITY_ID` through the call chain without naming it explicitly at each level — the same mechanism `deploy.yaml` and `scan.yaml` already used for their own, unrelated Infisical needs.

### Matching: ARC runners don't populate the classic `labels` field

The check matches on runner **name**, not `labels`, and requires `busy == false`:

```yaml
select(.status == "online") | select(.busy == false) | select(.name | startswith("homescale-runners-"))
```

ARC-managed runners report `labels: []` on this API regardless of scale set — verified against the live pool, every runner. ARC always names scale-set runners `<runnerScaleSetName>-<suffix>-runner-<suffix>`, so matching by name prefix is reliable.

### Failure modes

The check itself is defensive: if `RUNNER_CHECK_TOKEN` isn't set, or any failure calling the GitHub API (rate limit, transient error), it degrades to `self_hosted: false` rather than failing the `homescale-runners` job outright — since every other job `needs` it, a hard failure there would skip all of CI instead of just falling back to cloud runners. The one gap worth knowing about: the check runs once at the start of each workflow run, so if the pool disappears *mid-run* (rare — e.g. right after a passing check), a job already routed to `homescale-runners` will queue until it hits its own timeout rather than instantly falling back.

This means the pool being down, unreachable, or not yet set up is never a hard failure — CI just runs slower, exactly as it did before this pool existed.

## Tuning

- `minRunners` / `maxRunners` — set in `apps/github-runner/app.yaml` under `values.gha-runner-scale-set`.
- Dependencies baked into the runner image — `apps/github-runner/Dockerfile`. The Ansible collections are pulled from `infra/ansible/requirements.yml` (via `ansible-galaxy collection install -r`) rather than pinned separately in the Dockerfile, so there's nothing to keep in sync manually — the deployed image always reflects the current file.
- The image in `apps/github-runner/app.yaml` is still committed as `ghcr.io/homescalecloud/github-runner:latest`, but that's a placeholder — same pattern as `homepage`/`maxmorris-io`. ArgoCD Image Updater (`apps/argocd/templates/imageupdater.yaml`) watches the repo for full git-SHA tags and patches the running pod's image in-cluster (`writeBackConfig.method: argocd`, never a git commit), targeting `gha-runner-scale-set.template.spec.containers[0].image` via the `helm.spec` manifest target — that vendored chart takes one combined `image:` string rather than separate `repository`/`tag` fields, unlike our own charts. Renovate is already excluded from all `ghcr.io/homescalecloud/*` images via `renovate.json`, so it never fights Image Updater over this tag. This replaced an earlier `:latest`-only setup after Spegel (the cluster's P2P registry mirror) was found serving a stale cached digest for the mutable `:latest` tag — pinning to immutable SHA tags sidesteps that ambiguity entirely.
- `python-is-python3` is installed explicitly. The base image only has `python3`; `pre-commit/action` (and potentially other third-party actions) hardcode `python`, which doesn't otherwise exist on PATH.
- Helm is installed from a `get.helm.sh` binary download rather than the official `get-helm-3` script, which depends on `api.github.com` for its version lookup — a smaller, more robust dependency surface, though not the fix for the issue below (that turned out to be deeper than any one specific host).

### Known issue: this image can't reliably be built on the pool it powers

`build.yaml`'s `docker` job deliberately **always** builds `apps/github-runner` on `ubuntu-latest`, never on the `homescale-runners` pool itself, even when the pool is otherwise healthy and every other app happily builds there. Multiple attempts to build it self-hosted hit slow (multi-minute), inconsistent SSL/TLS connection failures reaching *external* hosts — always from inside the nested dind build container specifically, never from the pod's own network path (a plain debug pod in the same namespace reaches the same hosts in under 200ms) and not tied to any one specific host (moved between `api.github.com`, `get.helm.sh`, different failures each time). That points at something in the dind sidecar's own network stack — an MTU mismatch with Cilium's VXLAN overlay is the leading unconfirmed hypothesis — rather than anything fixable from the Dockerfile.

Building this specific image only on GitHub-hosted infra avoids the problem entirely, and avoids a nastier failure mode: if the pool's own image can only ever be rebuilt by a healthy pool, a broken pool can never be fixed by pushing a fix. If you want to actually root-cause the dind networking issue, it needs `pods/exec` in the `github-runner` namespace to inspect the dind container's network config directly, which isn't broadly granted.

### Trivy scan scope

`build.yaml`'s per-image Trivy scan (`skip-dirs`/`skip-files`, `github-runner`-specific) deliberately excludes: everything bundled by the `ghcr.io/actions/actions-runner` base image itself (`docker`/`containerd`/`runc`/`buildx`, its own Node.js toolchain under `home/runner/externals`), and the five tools this Dockerfile installs as the latest official release from their own channel (`gh`, `tailscale`, `terraform`, `helm`, `kubectl`). Every finding hit there so far has been the same shape — an official upstream binary statically compiled with a Go (or Node) stdlib version a few patches behind the latest security fix, with no newer release to pin to instead. That's accepted supply-chain risk inherent to depending on these tools at all, not something fixable from this Dockerfile; the scan still catches anything in packages we actually pin ourselves (the `pip3 install` block).

### Building the image locally

`infra/ansible/requirements.yml` lives outside `apps/github-runner/`, and Docker can't `COPY` from outside its build context, so `build.yaml`'s `docker` job copies it in (`apps/github-runner/requirements.yml`, gitignored) right before building. Do the same locally first:

```bash
cp infra/ansible/requirements.yml apps/github-runner/requirements.yml
docker build apps/github-runner -t github-runner
```
