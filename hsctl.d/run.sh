#!/usr/bin/env bash
# hsctl run — run a playbook or script, either remotely (dispatches
# .github/workflows/deploy.yaml on GitHub Actions and follows the triggered run) or
# locally (clones main fresh and runs it directly against that checkout).
#
# <name> is one of a small set of known jobs — bootstrap-core, bootstrap-cluster,
# omni-sync, terraform — or, in local mode only, the bare filename (without .yml) of any
# other playbook under infra/ansible/playbooks/.
#
# bootstrap-core/bootstrap-cluster get special local-secrets handling for their playbook
# (see _run_bootstrap_local); terraform gets the same treatment for its own Infisical
# universal-auth creds (see _run_terraform_local) — needed to bootstrap core itself (and
# the rest of infra/terraform) from a human's own machine, before CI/Tailscale can reach
# anything.
#
# Local mode never runs against $HSCTL_REPO_ROOT — it clones HomeScaleCloud/homescale@main
# fresh into a temp dir instead (_run_local_clone_repo), so it always matches main.

# Cleanup registry: a later `trap ... EXIT` call replaces any earlier one instead of
# stacking, so independent cleanups register a path here rather than trapping directly.
_run_cleanup_paths=()
_run_register_cleanup() { _run_cleanup_paths+=("$1"); }
_run_cleanup() {
    local p
    for p in "${_run_cleanup_paths[@]:-}"; do
        [[ -n "$p" ]] && rm -rf "$p"
    done
    return 0
}
trap _run_cleanup EXIT

run_usage() {
    echo "Usage: hsctl run <name> [--cluster <name>] [--arg key=value]... [-e|--execution-mode local|remote] [--dry-run] [--chain <name>[,<name>...]] [--git-ref <ref>]"
    echo ""
    echo "<name> is one of:"
    echo "  bootstrap-core      bootstrap the core cluster (playbook)"
    echo "  bootstrap-cluster   bootstrap workload clusters (all, or one via --cluster) (playbook)"
    echo "  omni-sync           sync every cluster template + machine class into Omni (script)"
    echo "  terraform           plan/apply infra/terraform (script) — the only way to bootstrap"
    echo "                      core itself, before CI can reach it over Tailscale"
    echo "  <anything else>     (local mode only) any other playbook under"
    echo "                      infra/ansible/playbooks/<name>.yml"
    echo ""
    echo "Options:"
    echo "  --arg key=value             (repeatable, remote mode only) 'clusters'/'machineclasses'"
    echo "                              (omni-sync) fold into that workflow_dispatch input;"
    echo "                              anything else is passed as an extra ansible -e key=value"
    echo "                              to the generic-playbook fallback job only"
    echo "  --cluster <name>            sugar for --arg cluster=<name> — meaningful for"
    echo "                              bootstrap-cluster (-e target=<name>), terraform"
    echo "                              (scopes the plan/apply to that cluster's own resources),"
    echo "                              and omni-sync (syncs just that one cluster)"
    echo "  -e, --execution-mode <mode> 'local' or 'remote' (default: remote). remote dispatches"
    echo "                              .github/workflows/deploy.yaml via 'gh workflow run' and"
    echo "                              follows the triggered run (requires 'gh auth login' and"
    echo "                              write access to HomeScaleCloud/homescale). local clones"
    echo "                              main fresh (via gh) and runs <name> directly against it —"
    echo "                              still required for the very first core bootstrap, or any"
    echo "                              time CI/Tailscale can't reach what you're changing yet."
    echo "  --dry-run                   terraform: plan only, no apply. omni-sync: adds --dry-run"
    echo "                              to its omnictl calls. Ignored by ansible playbooks."
    echo "  --chain <name>[,...]        (local mode only) run <name> plus this list"
    echo "                              (comma-separated, no spaces) in sequence against the same"
    echo "                              checkout. Not supported in -e remote mode — GitHub Actions'"
    echo "                              workflow_dispatch can't compose an arbitrary step sequence"
    echo "                              at dispatch time; run each one separately with its own"
    echo "                              'hsctl run ... -e remote' instead."
    echo "  --git-ref <ref>              (remote mode only, default: main) branch/tag/SHA for"
    echo "                              deploy.yaml's own checkout step — lets a PR's own branch"
    echo "                              be planned instead of main's current content."
    exit 1
}

# Fetch a secrets folder from Infisical via the caller's already-authenticated CLI session,
# retrying once (against infisical init or infisical login, whichever it actually needs —
# see hsctl_infisical_call) if the first attempt fails.
# Usage: _run_infisical_secrets <path>   -> flat JSON object {KEY: value, ...} on stdout
_run_infisical_secrets() {
    local path="$1" raw
    raw=$(hsctl_infisical_call export --silent --env=prod --path="$path" --format=json) || {
        hsctl_log_error "failed to fetch secrets from Infisical (path $path)"
        return 1
    }
    jq 'map({(.key): .value}) | add // {}' <<< "$raw"
}

# Run bootstrap-core or bootstrap-cluster locally, pre-fetching secrets via the local
# Infisical CLI session and handing them to Ansible as hsctl_local_secrets.
_run_bootstrap_local() {
    local playbook="$1" cluster="$2" dry_run="$3" repo_root="$4"

    command -v infisical &>/dev/null || { echo "hsctl run: the infisical CLI is required (brew install infisical)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    [[ -n "$cluster" && "$playbook" == "bootstrap-core" ]] && hsctl_log_info "--cluster is ignored for bootstrap-core"

    hsctl_log_info "fetching secrets from Infisical via local CLI session"
    local argocd_secrets infisical_op_secrets ci_secrets='{}'
    argocd_secrets=$(_run_infisical_secrets /k8s/argocd/deploy-key) || exit 1
    infisical_op_secrets=$(_run_infisical_secrets /k8s/infisical) || exit 1
    [[ "$playbook" == "bootstrap-core" ]] && { ci_secrets=$(_run_infisical_secrets /ci) || exit 1; }

    local extra_vars_file
    extra_vars_file=$(mktemp)
    chmod 600 "$extra_vars_file"
    _run_register_cleanup "$extra_vars_file"

    jq -n \
        --argjson argocd "$argocd_secrets" \
        --argjson infisical_op "$infisical_op_secrets" \
        --argjson ci "$ci_secrets" \
        '{hsctl_local: true, hsctl_local_secrets: {argocd_deploy_key: $argocd, infisical_operator: $infisical_op, ci: $ci}}' \
        > "$extra_vars_file"

    (
        export HSCTL_REPO_ROOT="$repo_root" # so a nested `hsctl get machines` (via the inventory/machines dynamic inventory script) resolves against the same fresh checkout
        cd "$repo_root/infra/ansible" || exit 1

        case "$playbook" in
            bootstrap-core)
                hsctl_log_action "running bootstrap-core.yml"
                ansible-playbook playbooks/bootstrap-core.yml -e cluster_name=core -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
                ;;
            bootstrap-cluster)
                hsctl_log_action "running bootstrap-cluster.yml${cluster:+ (target: $cluster)}"
                if [[ -n "$cluster" ]]; then
                    ansible-playbook playbooks/bootstrap-cluster.yml -e target="$cluster" -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
                else
                    ansible-playbook playbooks/bootstrap-cluster.yml -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
                fi
                ;;
        esac
    )
}

# Run any other playbook locally, as-is — no local secrets handling (see module comment).
_run_generic_local() {
    local playbook="$1" cluster="$2" dry_run="$3" repo_root="$4"
    local playbook_file="$repo_root/infra/ansible/playbooks/$playbook.yml"

    [[ -f "$playbook_file" ]] || { hsctl_log_error "no such playbook: infra/ansible/playbooks/$playbook.yml"; exit 1; }

    (
        export HSCTL_REPO_ROOT="$repo_root" # so a nested `hsctl get machines` (via the inventory/machines dynamic inventory script) resolves against the same fresh checkout
        cd "$repo_root/infra/ansible" || exit 1
        hsctl_log_action "running $playbook.yml${cluster:+ (target: $cluster)}"
        if [[ -n "$cluster" ]]; then
            ansible-playbook "playbooks/$playbook.yml" -e target="$cluster" -e "dry_run=$dry_run"
        else
            ansible-playbook "playbooks/$playbook.yml" -e "dry_run=$dry_run"
        fi
    )
}

# Run infra/terraform/plan-apply.sh locally, pre-fetching the "ci" identity's universal-auth
# credentials via the caller's own Infisical CLI session (there's no GitHub OIDC token to
# present outside an Actions runner — see providers.tf) and exporting the TF_VAR_* the
# provider needs straight into the script's environment.
_run_terraform_local() {
    local cluster="$1" dry_run="$2" repo_root="$3"

    command -v infisical &>/dev/null || { echo "hsctl run: the infisical CLI is required (brew install infisical)" >&2; exit 1; }
    command -v terraform &>/dev/null || { echo "hsctl run: terraform is required" >&2; exit 1; }

    hsctl_log_info "fetching terraform's Infisical universal-auth credentials via local CLI session"
    local secrets
    secrets=$(_run_infisical_secrets /ci) || exit 1

    (
        export TF_VAR_infisical_auth_method="universal"
        export TF_VAR_infisical_universal_auth_client_id TF_VAR_infisical_universal_auth_client_secret TF_VAR_infisical_org_id
        export CLOUDFLARE_API_TOKEN TF_TOKEN_app_terraform_io
        TF_VAR_infisical_universal_auth_client_id=$(jq -r '.INFISICAL_CI_CLIENT_ID // ""' <<<"$secrets")
        TF_VAR_infisical_universal_auth_client_secret=$(jq -r '.INFISICAL_CI_CLIENT_SECRET // ""' <<<"$secrets")
        TF_VAR_infisical_org_id=$(jq -r '.INFISICAL_ORG_ID // ""' <<<"$secrets")
        CLOUDFLARE_API_TOKEN=$(jq -r '.CLOUDFLARE_API_TOKEN // ""' <<<"$secrets")
        TF_TOKEN_app_terraform_io=$(jq -r '.TF_TOKEN_app_terraform_io // ""' <<<"$secrets")
        export CLUSTER="$cluster" DRY_RUN="$dry_run"

        cd "$repo_root" || exit 1
        hsctl_log_action "running infra/terraform/plan-apply.sh${cluster:+ (cluster: $cluster)}${dry_run:+, dry_run=$dry_run}"
        bash infra/terraform/plan-apply.sh
    )
}

# Run infra/omni/sync.sh locally — no special secrets handling, OMNI_SERVICE_ACCOUNT_KEY
# is picked up the same way `hsctl get`/`hsctl machine` already resolve Omni access
# (local omniconfig or the env var, if already set).
_run_omni_sync_local() {
    local cluster="$1" dry_run="$2" repo_root="$3"

    (
        export REPO_DIR="$repo_root" DRY_RUN="$dry_run"
        [[ -n "$cluster" ]] && export CLUSTERS="$cluster"
        cd "$repo_root" || exit 1
        hsctl_log_action "running infra/omni/sync.sh${cluster:+ (cluster: $cluster)}${dry_run:+, dry_run=$dry_run}"
        bash infra/omni/sync.sh
    )
}

# Clones `main` fresh into a temp dir, once per `hsctl run` invocation (not per chained
# playbook). Doesn't call _run_register_cleanup itself — this runs in a $(...) subshell,
# so the caller registers the returned path in its own, non-subshell scope instead.
_run_local_clone_repo() {
    command -v gh &>/dev/null || { echo "hsctl run: gh is required for local runs (brew install gh)" >&2; exit 1; }

    local tmpdir
    tmpdir=$(mktemp -d)
    if ! gh repo clone HomeScaleCloud/homescale "$tmpdir" -- --depth 1 --branch main --quiet; then
        hsctl_log_error "failed to clone HomeScaleCloud/homescale@main (check: gh auth status)"
        rm -rf "$tmpdir"
        return 1
    fi
    echo "$tmpdir"
}

_run_local() {
    local name="$1" cluster="$2" dry_run="$3" repo_root="$4"

    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    case "$name" in
        bootstrap-core|bootstrap-cluster)
            command -v ansible-playbook &>/dev/null || { echo "hsctl run: ansible-playbook is required (brew install ansible)" >&2; exit 1; }
            _run_bootstrap_local "$name" "$cluster" "$dry_run" "$repo_root"
            ;;
        terraform)
            _run_terraform_local "$cluster" "$dry_run" "$repo_root"
            ;;
        omni-sync)
            command -v omnictl &>/dev/null || { echo "hsctl run: omnictl is required" >&2; exit 1; }
            _run_omni_sync_local "$cluster" "$dry_run" "$repo_root"
            ;;
        *)
            command -v ansible-playbook &>/dev/null || { echo "hsctl run: ansible-playbook is required (brew install ansible)" >&2; exit 1; }
            _run_generic_local "$name" "$cluster" "$dry_run" "$repo_root"
            ;;
    esac
}

# _run_remote <name> <cli-args-json> <dry_run> <chain_raw> <git_ref> — dispatches
# .github/workflows/deploy.yaml via `gh workflow run` and follows the triggered run.
# cli_args_json's "cluster" key becomes the 'cluster' workflow_dispatch input (bootstrap-
# cluster's target, terraform's scoping, or omni-sync's single-cluster filter);
# "machineclasses" becomes the 'machineclasses' input (omni-sync only); any other key is
# folded into a space-separated "key=value ..." string for the 'extra_args' input, which
# only the generic-ansible-playbook fallback job consumes.
_run_remote() {
    local name="$1" cli_args_json="$2" dry_run="$3" chain_raw="$4" git_ref="${5:-main}"
    local repo="HomeScaleCloud/homescale"

    [[ -n "$chain_raw" ]] && { hsctl_log_error "--chain isn't supported in -e remote mode — GitHub Actions workflow_dispatch can't compose an arbitrary step sequence at dispatch time. Run each template separately (hsctl run <name> -e remote), or use -e local to chain against one checkout."; exit 1; }

    command -v gh &>/dev/null || { echo "hsctl run: gh is required (brew install gh)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    local cluster machineclasses extra_args
    cluster=$(jq -r '.cluster // ""' <<<"$cli_args_json")
    machineclasses=$(jq -r '.machineclasses // ""' <<<"$cli_args_json")
    extra_args=$(jq -r 'with_entries(select(.key != "cluster" and .key != "machineclasses")) | to_entries | map("\(.key)=\(.value)") | join(" ")' <<<"$cli_args_json")

    hsctl_log_action "dispatching deploy.yaml (job=$name${cluster:+, cluster=$cluster}${machineclasses:+, machineclasses=$machineclasses}${dry_run:+, dry_run=$dry_run}, ref=$git_ref) on $repo"
    local before_ts
    before_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gh workflow run deploy.yaml -R "$repo" --ref "$git_ref" \
        -f "job=$name" -f "cluster=$cluster" -f "machineclasses=$machineclasses" \
        -f "dry_run=$dry_run" -f "extra_args=$extra_args" \
        || { hsctl_log_error "failed to dispatch deploy.yaml — check: gh auth status"; exit 1; }

    hsctl_log_info "waiting for the run to appear..."
    local attempt run_id=""
    for attempt in $(seq 1 30); do
        sleep 2
        run_id=$(gh run list -R "$repo" --workflow=deploy.yaml --event=workflow_dispatch \
            --limit 5 --json databaseId,createdAt \
            --jq "[.[] | select(.createdAt >= \"$before_ts\")] | sort_by(.createdAt) | last | .databaseId // empty" \
            2>/dev/null) || true
        [[ -n "$run_id" ]] && break
    done

    if [[ -z "$run_id" ]]; then
        hsctl_log_error "dispatched but couldn't find the resulting run — check: gh run list -R $repo --workflow=deploy.yaml"
        exit 1
    fi

    hsctl_log_info "run: https://github.com/$repo/actions/runs/$run_id"
    gh run watch "$run_id" -R "$repo" --exit-status
}

run_main() {
    local playbook="" cluster="" mode="remote" dry_run="false" playbook_set=false
    local chain_raw="" arg_kvs=() git_ref="main"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster) cluster="${2:-}"; [[ -z "$cluster" ]] && run_usage; shift 2 ;;
            --arg)
                [[ -z "${2:-}" || "${2:-}" != *=* ]] && run_usage
                arg_kvs+=("$2"); shift 2 ;;
            -e|--execution-mode)
                mode="${2:-}"
                [[ "$mode" != "local" && "$mode" != "remote" ]] && run_usage
                shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            --chain)
                chain_raw="${2:-}"; [[ -z "$chain_raw" ]] && run_usage
                shift 2 ;;
            --git-ref)
                git_ref="${2:-}"; [[ -z "$git_ref" ]] && run_usage
                shift 2 ;;
            -h|--help) run_usage ;;
            --*) echo "hsctl run: unknown flag '$1'" >&2; run_usage ;;
            *)
                [[ "$playbook_set" == true ]] && { echo "hsctl run: unexpected argument '$1'" >&2; run_usage; }
                playbook="$1"; playbook_set=true; shift ;;
        esac
    done

    [[ -z "$playbook" ]] && { echo "hsctl run: a name is required" >&2; run_usage; }

    local local_repo_root=""
    if [[ "$mode" == "local" ]]; then
        local_repo_root=$(_run_local_clone_repo) || exit 1
        _run_register_cleanup "$local_repo_root"
    fi

    if [[ "$mode" == "remote" ]]; then
        command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }
        local cli_args_json="{}"
        if [[ ${#arg_kvs[@]} -gt 0 ]]; then
            cli_args_json=$(jq -n --args '
                $ARGS.positional | map(split("=") | {(.[0]): (.[1:] | join("="))}) | add // {}' \
                -- "${arg_kvs[@]}")
        fi
        [[ -n "$cluster" ]] && cli_args_json=$(jq --arg v "$cluster" '. + {cluster: $v}' <<<"$cli_args_json")
        _run_remote "$playbook" "$cli_args_json" "$dry_run" "$chain_raw" "$git_ref"
    else
        local chain_templates=() p
        if [[ -n "$chain_raw" ]]; then
            local IFS=','
            read -r -a chain_templates <<< "$chain_raw"
            unset IFS
        fi
        for p in "$playbook" "${chain_templates[@]:-}"; do
            [[ -z "$p" ]] && continue
            _run_local "$p" "$cluster" "$dry_run" "$local_repo_root"
        done
    fi
}
