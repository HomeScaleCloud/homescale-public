# GitHub Actions Self-Hosted Runners

CI can run on a self-hosted runner pool on `boa1-prod` instead of GitHub-hosted `ubuntu-latest` runners, using a custom image (`apps/github-runner/Dockerfile`) with dependencies pre-installed so jobs don't reinstall Terraform, Helm, Ansible, etc. on every run. If the pool is unavailable for any reason, CI transparently falls back to GitHub-hosted runners and installs dependencies as before — no workflow breaks either way.

## Architecture

Two catalog apps, deployed only to `boa1-prod`:

- **`apps/github-runner-controller`** — [Actions Runner Controller](https://github.com/actions/actions-runner-controller) (ARC), the `gha-runner-scale-set-controller` chart. One instance, cluster-wide.
- **`apps/github-runner`** — the runner pool itself, the `gha-runner-scale-set` chart, configured with our custom image and `containerMode.type: dind` (a Docker-in-Docker sidecar, needed so `docker/build-push-action` in `build.yaml` has a real daemon to talk to). Runner scale set / `runs-on` label: `homescale-runners`.

Both apps share the `github-runner` namespace — safe because they're still two separate Helm releases/ArgoCD Applications (only *merging them into one chart* hit the naming bug below), and ARC's `controllerServiceAccount` value exists precisely to let the runner scale set reference the controller's ServiceAccount across releases. One gotcha from sharing: the catalog chart only applies `podSecurity` labels from the *first* app processed for a given namespace (by file glob order — see `docs/architecture/apps.md`), so both `app.yaml`s set `podSecurity: privileged` rather than relying on only the runner app to do it.

They're **not** merged into a single chart/Application, even though `gha-runner-scale-set-controller` and `gha-runner-scale-set` could technically be declared as two dependencies of one `Chart.yaml`: both charts independently define a generically-named internal Helm template (`gha-base-name`, meaning something different in each), and Helm's `define` blocks share one global namespace across a parent chart and its subcharts — combining them silently corrupted the runner scale set's resource names with the controller's naming. Confirmed by testing it; reverted.

`minRunners` is `1`, not `0`: with autoscale-to-zero, no runner would ever be registered while idle, and CI's "is the pool available" check (below) would have nothing to observe. One warm runner keeps that check meaningful and avoids cold-start delay on the first job of a run. `maxRunners` is `4`.

## Setting it up

### 1. Create a GitHub App

In the `HomeScaleCloud` org → **Settings → Developer settings → GitHub Apps → New GitHub App**:

- Repository permissions: `Actions: Read-only`, `Administration: Read & write`
- Organization permissions: `Self-hosted runners: Read & write`
- No webhook, no user authorization needed
- Generate a private key (downloads a `.pem`)
- Install the app on the org (all repos, so any future repo can use the pool too)

### 2. Add secrets to Infisical

At `/k8s/github-runner` (prod env):

| Key | Value |
|-----|-------|
| `github_app_id` | The App ID from the app's settings page |
| `github_app_installation_id` | The installation ID (visible in the URL after installing the app on the org) |
| `github_app_private_key` | The full contents of the downloaded `.pem` |

These are synced into the `github-runner` namespace as the `github-runner-github-app` secret by `apps/github-runner/templates/secret.yaml`, and referenced by the chart's `githubConfigSecret` value.

### 3. Make the runner image public

The `homescale` repo is private, so `ghcr.io/homescalecloud/github-runner` defaults to a private package on first push — which the cluster can't pull without an image pull secret. Since the image itself has no secrets baked in (just public tooling on top of the public `ghcr.io/actions/actions-runner` base), the simplest fix is to make the package public instead of managing a pull secret: after the first successful build (merge a change under `apps/github-runner/` to `main`), go to the package's settings on `github.com/orgs/HomeScaleCloud/packages` and change its visibility to public.

## How the CI fallback works

Every job in `scan.yaml`, `build.yaml`, `deploy.yaml`, and `mirror.yaml` depends on a `homescale-runners` job (`.github/workflows/homescale-runners.yaml`, itself a nested reusable workflow), which queries `GET /repos/HomeScaleCloud/homescale/actions/runners` for an online runner labeled `homescale-runners`. Downstream jobs pick their `runs-on` from that result:

```yaml
runs-on: ${{ needs.homescale-runners.outputs.self_hosted == 'true' && 'homescale-runners' || 'ubuntu-latest' }}
```

Steps that install something the custom image already bakes in (Terraform, Helm, Ansible, mkdocs-material, git-filter-repo, etc.) are guarded the same way, so they only run on the GitHub-hosted fallback:

```yaml
if: needs.homescale-runners.outputs.self_hosted != 'true'
```

`claude.yml` (the `@claude` mention bot) intentionally does **not** go through this — it's not part of the build/test/deploy pipeline and has no heavy dependency-install steps to save.

The check itself is defensive: any failure calling the GitHub API (rate limit, transient error) degrades to `self_hosted: false` rather than failing the `homescale-runners` job outright — since every other job `needs` it, a hard failure there would skip all of CI instead of just falling back to cloud runners. The one gap worth knowing about: the check runs once at the start of each workflow run, so if the pool disappears *mid-run* (rare — e.g. right after a passing check), a job already routed to `homescale-runners` will queue until it hits its own timeout rather than instantly falling back.

Every reusable workflow in the call chain must declare `actions: read` in its own top-level `permissions:` block for the nested `homescale-runners` call to have API access — GitHub scopes the token for a reusable workflow call to the intersection of what the caller declares at each level, not just the top-level `ci.yaml`. `scan.yaml`, `build.yaml`, `deploy.yaml`, and `mirror.yaml` all declare it.

This means the pool being down, unreachable, or not yet set up is never a hard failure — CI just runs slower, exactly as it did before this pool existed.

## Tuning

- `minRunners` / `maxRunners` — set in `apps/github-runner/app.yaml` under `values.gha-runner-scale-set`.
- Dependencies baked into the runner image — `apps/github-runner/Dockerfile`. The Ansible collections are pulled from `infra/ansible/requirements.yml` (via `ansible-galaxy collection install -r`) rather than pinned separately in the Dockerfile, so there's nothing to keep in sync manually — the deployed image always reflects the current file.
- The image is tagged `:latest` rather than pinned to a git SHA (unlike the general convention for app images) so that a Dockerfile change rolls out on the next merge without a two-step PR dance — this is CI-internal infra, not a user-facing app.

### Trivy scan scope

`build.yaml`'s per-image Trivy scan (`skip-dirs`/`skip-files`, `github-runner`-specific) deliberately excludes: everything bundled by the `ghcr.io/actions/actions-runner` base image itself (`docker`/`containerd`/`runc`/`buildx`, its own Node.js toolchain under `home/runner/externals`), and the five tools this Dockerfile installs as the latest official release from their own channel (`gh`, `tailscale`, `terraform`, `helm`, `kubectl`). Every finding hit there so far has been the same shape — an official upstream binary statically compiled with a Go (or Node) stdlib version a few patches behind the latest security fix, with no newer release to pin to instead. That's accepted supply-chain risk inherent to depending on these tools at all, not something fixable from this Dockerfile; the scan still catches anything in packages we actually pin ourselves (the `pip3 install` block).

### Building the image locally

`infra/ansible/requirements.yml` lives outside `apps/github-runner/`, and Docker can't `COPY` from outside its build context, so `build.yaml`'s `docker` job copies it in (`apps/github-runner/requirements.yml`, gitignored) right before building. Do the same locally first:

```bash
cp infra/ansible/requirements.yml apps/github-runner/requirements.yml
docker build apps/github-runner -t github-runner
```
