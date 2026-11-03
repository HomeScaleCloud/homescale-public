#!/usr/bin/env bash
# Dispatch workflows remotely or run commands from HSCTL_REPO_ROOT locally.
# Bootstrap and Terraform fetch local Infisical credentials; TOPF uses its provider.

# Register cleanup paths under one EXIT trap.
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
    echo "       hsctl run bootstrap-cluster --cluster <name> -e local --nodes <file>"
    echo "       hsctl run topf --cluster <name> <topf args...>"
    echo ""
    echo "<name> is one of:"
    echo "  bootstrap-cluster   bootstrap workload clusters (all, or one via --cluster) (playbook)"
    echo "  update-cluster      reconcile Talos/Kubernetes versions and config (playbook)"
    echo "  terraform           plan/apply infra/terraform (script) — cloud resources, Tailscale"
    echo "                      ACL, Infisical project structure; no Talos cluster provisioning"
    echo "                      (see 'topf')"
    echo "  topf                run native TOPF against clusters/<cluster>/ (--cluster required)."
    echo "                      Uses the existing Infisical CA bundle and a local private cache."
    echo "                      Prefix --refresh-secrets to refresh, --init-secrets for first use."
    echo "                      Native TOPF flags, including apply --dry-run, pass through."
    echo "  <anything else>     (local mode only) any other playbook under"
    echo "                      infra/ansible/playbooks/<name>.yml"
    echo ""
    echo "Options:"
    echo "  --arg key=value             (repeatable, remote mode only) anything other than"
    echo "                              'cluster' is passed as an extra ansible -e key=value to"
    echo "                              the generic-playbook fallback job only"
    echo "  --cluster <name>            sugar for --arg cluster=<name> — meaningful for"
    echo "                              bootstrap-cluster/update-cluster (-e target=<name>) and terraform"
    echo "                              (scopes the plan/apply to that cluster's own resources)."
    echo "                              Required for topf — see above."
    echo "  --nodes <file>              (bootstrap-cluster, local mode only) YAML/JSON file"
    echo "                              listing this cluster's new nodes as {name, dhcp_ip,"
    echo "                              static_ip} — folds the full Talos bootstrap (render,"
    echo "                              apply, wait for the static IP, bootstrap etcd) into"
    echo "                              this run, ahead of the usual cilium/argocd setup."
    echo "                              Requires --cluster and -e local. Only for a cluster's"
    echo "                              very first bootstrap — adding a node to an already"
    echo "                              running cluster uses 'hsctl run topf'"
    echo "                              sequence against that one node (see CLAUDE.md)."
    echo "  -e, --execution-mode <mode> 'local' or 'remote' (default: remote). remote dispatches"
    echo "                              .github/workflows/deploy.yaml via 'gh workflow run' and"
    echo "                              follows the triggered run (requires 'gh auth login' and"
    echo "                              write access to HomeScaleCloud/homescale). local runs"
    echo "                              directly against HSCTL_REPO_ROOT, including local changes —"
    echo "                              still required for the very first cluster bootstrap, or"
    echo "                              any time CI/Tailscale can't reach what you're changing yet."
    echo "  --dry-run                   terraform/update-cluster: preview only. Ignored by bootstrap playbooks."
    echo "  --chain <name>[,...]        (local mode only) run <name> plus this list"
    echo "                              (comma-separated, no spaces) in sequence against the same"
    echo "                              checkout. Not supported in -e remote mode — GitHub Actions'"
    echo "                              workflow_dispatch can't compose an arbitrary step sequence"
    echo "                              at dispatch time; run each one separately with its own"
    echo "                              'hsctl run ... -e remote' instead."
    echo "  --git-ref <ref>              (remote only, default: main) branch/tag for"
    echo "                              deploy.yaml checkout — lets a PR's own branch"
    echo "                              be planned instead of main's current content."
    exit 1
}

# Export Infisical secrets as a JSON object using the existing CLI session.
_run_infisical_secrets() {
    local path="$1" raw
    if ! raw=$(hsctl_infisical_call export --silent --env=prod --path="$path" --format=json); then
        # Preserve the empty-object result for missing folders.
        if grep -q "was not found" "/tmp/.hsctl-infisical-err.$$" 2>/dev/null; then
            echo '{}'
            return 0
        fi
        hsctl_log_error "failed to fetch secrets from Infisical (path $path)"
        return 1
    fi
    jq 'map({(.key): .value}) | add // {}' <<< "$raw"
}

# Prepare the pinned collections before invoking a local playbook.
_run_ansible() {
    ansible-galaxy collection install -r "$HSCTL_REPO_ROOT/infra/ansible/requirements.yml" >&2
    ansible-playbook "$@"
}

# Pass local service credentials to Ansible in a private extra-vars file.
_run_bootstrap_local() {
    local cluster="$1" dry_run="$2" repo_root="$3" nodes_file="$4"

    command -v infisical &>/dev/null || { echo "hsctl run: the infisical CLI is required (brew install infisical)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    local bootstrap_nodes_json='[]'
    if [[ -n "$nodes_file" ]]; then
        command -v yq &>/dev/null || { echo "hsctl run: yq is required (brew install yq)" >&2; exit 1; }
        [[ -f "$nodes_file" ]] || { hsctl_log_error "no such file: $nodes_file"; exit 1; }
        bootstrap_nodes_json=$(yq -o=json '.' "$nodes_file") || { hsctl_log_error "failed to parse $nodes_file as YAML/JSON"; exit 1; }
        jq -e 'type == "array" and length > 0 and
            all(.[]; (.name | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
                (.dhcp_ip | type == "string" and test("^[0-9a-fA-F:.]+$")) and
                (.static_ip | type == "string" and test("^[0-9a-fA-F:.]+$"))) and
            ((map(.name) | unique | length) == length) and
            ((map(.static_ip) | unique | length) == length) and
            ((map(.dhcp_ip) | unique | length) == length)' <<<"$bootstrap_nodes_json" >/dev/null ||
            { hsctl_log_error "nodes must be a nonempty list of unique {name, dhcp_ip, static_ip} entries"; exit 1; }
    fi

    hsctl_log_info "fetching secrets from Infisical via local CLI session"
    local argocd_secrets infisical_op_secrets
    argocd_secrets=$(_run_infisical_secrets /k8s/argocd/deploy-key) || exit 1
    infisical_op_secrets=$(_run_infisical_secrets /k8s/infisical) || exit 1

    local extra_vars_file
    extra_vars_file=$(mktemp)
    chmod 600 "$extra_vars_file"
    _run_register_cleanup "$extra_vars_file"

    jq -n \
        --argjson argocd "$argocd_secrets" \
        --argjson infisical_op "$infisical_op_secrets" \
        --argjson bootstrap_nodes "$bootstrap_nodes_json" \
        --arg hsctl_repo_root "$HSCTL_REPO_ROOT" \
        '{hsctl_local: true, hsctl_repo_root: $hsctl_repo_root, bootstrap_nodes: $bootstrap_nodes, hsctl_local_secrets: {argocd_deploy_key: $argocd, infisical_operator: $infisical_op}}' \
        > "$extra_vars_file"

    (
        export HSCTL_REPO_ROOT="$repo_root"
        cd "$repo_root/infra/ansible" || exit 1

        hsctl_log_action "running bootstrap-cluster.yml${cluster:+ (target: $cluster)}"
        if [[ -n "$cluster" ]]; then
            _run_ansible playbooks/bootstrap-cluster.yml -e target="$cluster" -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
        else
            _run_ansible playbooks/bootstrap-cluster.yml -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
        fi
    )
}

# Run other playbooks from the current checkout.
_run_generic_local() {
    local playbook="$1" cluster="$2" dry_run="$3" repo_root="$4"
    local playbook_file="$repo_root/infra/ansible/playbooks/$playbook.yml"

    [[ -f "$playbook_file" ]] || { hsctl_log_error "no such playbook: infra/ansible/playbooks/$playbook.yml"; exit 1; }

    (
        export HSCTL_REPO_ROOT="$repo_root"
        cd "$repo_root/infra/ansible" || exit 1
        hsctl_log_action "running $playbook.yml${cluster:+ (target: $cluster)}"
        if [[ -n "$cluster" ]]; then
            _run_ansible "playbooks/$playbook.yml" -e hsctl_local=true -e target="$cluster" -e "dry_run=$dry_run"
        else
            _run_ansible "playbooks/$playbook.yml" -e hsctl_local=true -e "dry_run=$dry_run"
        fi
    )
}

# Supply Terraform universal-auth credentials from the local Infisical session.
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

_run_topf() {
    local cluster="$1"; shift
    local init_secrets=false refresh_secrets=false
    while [[ "${1:-}" == --init-secrets || "${1:-}" == --refresh-secrets ]]; do
        case "$1" in
            --init-secrets) init_secrets=true ;;
            --refresh-secrets) refresh_secrets=true ;;
        esac
        shift
    done
    [[ -n "$cluster" && $# -gt 0 ]] || { hsctl_log_error "topf requires --cluster and a command"; return 1; }
    local project="$HSCTL_REPO_ROOT/clusters/$cluster"
    [[ -f "$project/topf.yaml" ]] || { hsctl_log_error "no such TOPF cluster: $cluster"; return 1; }
    command -v topf >/dev/null || { hsctl_log_error "topf is required (brew install postfinance/tap/topf)"; return 1; }
    (
        export HSCTL_REPO_ROOT
        export HSCTL_TOPF_INIT_SECRETS="$init_secrets"
        export HSCTL_TOPF_REFRESH_SECRETS="$refresh_secrets"
        cd "$project" || exit 1
        umask 077
        topf "$@"
    )
}

_run_local() {
    local name="$1" cluster="$2" dry_run="$3" repo_root="$4" nodes_file="${5:-}"

    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    case "$name" in
        bootstrap-cluster)
            command -v ansible-playbook &>/dev/null || { echo "hsctl run: ansible-playbook is required (brew install ansible)" >&2; exit 1; }
            _run_bootstrap_local "$cluster" "$dry_run" "$repo_root" "$nodes_file"
            ;;
        terraform)
            _run_terraform_local "$cluster" "$dry_run" "$repo_root"
            ;;
        *)
            command -v ansible-playbook &>/dev/null || { echo "hsctl run: ansible-playbook is required (brew install ansible)" >&2; exit 1; }
            _run_generic_local "$name" "$cluster" "$dry_run" "$repo_root"
            ;;
    esac
}

# Dispatch deploy.yaml; cluster selects the target, other arguments become extra_args.
_run_remote() {
    local name="$1" cli_args_json="$2" dry_run="$3" chain_raw="$4" git_ref="${5:-main}"
    local repo="HomeScaleCloud/homescale"

    [[ -n "$chain_raw" ]] && { hsctl_log_error "--chain isn't supported in -e remote mode — GitHub Actions workflow_dispatch can't compose an arbitrary step sequence at dispatch time. Run each template separately (hsctl run <name> -e remote), or use -e local to chain against one checkout."; exit 1; }

    command -v gh &>/dev/null || { echo "hsctl run: gh is required (brew install gh)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    local cluster extra_args
    cluster=$(jq -r '.cluster // ""' <<<"$cli_args_json")
    extra_args=$(jq -r 'with_entries(select(.key != "cluster")) | to_entries | map("\(.key)=\(.value)") | join(" ")' <<<"$cli_args_json")

    hsctl_log_action "dispatching deploy.yaml (job=$name${cluster:+, cluster=$cluster}${dry_run:+, dry_run=$dry_run}, ref=$git_ref) on $repo"
    local before_ts
    before_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gh workflow run deploy.yaml -R "$repo" --ref "$git_ref" \
        -f "job=$name" -f "cluster=$cluster" \
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
    if [[ "${1:-}" == "topf" ]]; then
        shift
        local cluster="" topf_args=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --cluster) cluster="${2:-}"; [[ -z "$cluster" ]] && run_usage; shift 2 ;;
                --) shift ;;
                *) topf_args+=("$1"); shift ;;
            esac
        done
        _run_topf "$cluster" "${topf_args[@]}"
        return $?
    fi

    local playbook="" cluster="" mode="remote" dry_run="false" playbook_set=false
    local chain_raw="" arg_kvs=() git_ref="main" git_ref_set=false nodes_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster) cluster="${2:-}"; [[ -z "$cluster" ]] && run_usage; shift 2 ;;
            --nodes) nodes_file="${2:-}"; [[ -z "$nodes_file" ]] && run_usage; shift 2 ;;
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
                git_ref="${2:-}"; git_ref_set=true; [[ -z "$git_ref" ]] && run_usage
                shift 2 ;;
            -h|--help) run_usage ;;
            --*) echo "hsctl run: unknown flag '$1'" >&2; run_usage ;;
            *)
                [[ "$playbook_set" == true ]] && { echo "hsctl run: unexpected argument '$1'" >&2; run_usage; }
                playbook="$1"; playbook_set=true; shift ;;
        esac
    done

    [[ -z "$playbook" ]] && { echo "hsctl run: a name is required" >&2; run_usage; }
    [[ -n "$nodes_file" && "$playbook" != "bootstrap-cluster" ]] && { echo "hsctl run: --nodes is only valid with bootstrap-cluster" >&2; run_usage; }
    [[ -n "$nodes_file" && "$mode" != "local" ]] && { echo "hsctl run: --nodes requires -e local (bootstrap needs direct LAN access)" >&2; run_usage; }
    [[ -n "$nodes_file" && -z "$cluster" ]] && { echo "hsctl run: --nodes requires --cluster" >&2; run_usage; }

    local local_repo_root=""
    if [[ "$mode" == "local" ]]; then
        [[ "$git_ref_set" == false ]] || { hsctl_log_error "--git-ref is remote-only; check out the desired revision locally"; return 1; }
        local_repo_root="$HSCTL_REPO_ROOT"
        [[ -d "$local_repo_root/infra/ansible" ]] || { hsctl_log_error "HSCTL_REPO_ROOT is not a HomeScale checkout: $local_repo_root"; return 1; }
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
            _run_local "$p" "$cluster" "$dry_run" "$local_repo_root" "$nodes_file"
        done
    fi
}
