#!/usr/bin/env bash
# hsctl run — run an Ansible playbook from infra/ansible/playbooks/, either locally or
# remotely via the Deploy workflow's "ansible" job (.github/workflows/deploy.yaml), which
# normally only fires on manual workflow_dispatch.
#
# `bootstrap-mgmt`/`bootstrap-cluster` are the built-in cluster bootstrap playbooks and get
# special handling below — see "Local secrets" — but any other playbook name under
# infra/ansible/playbooks/ works too, both locally and via --remote; it's just run as-is with
# no local secrets handling (see below). A playbook is always named explicitly — there's no
# "run everything" shortcut, since that's an easy way to fire off more infra changes than
# you meant to.
#
# Local secrets: CI authenticates to Infisical via GitHub Actions OIDC — a JWT that only
# exists inside an actual Actions run, so it can't be reproduced locally. For bootstrap-mgmt/
# bootstrap-cluster, local runs instead pre-fetch the same secrets via the caller's own
# `infisical` CLI session (browser SSO, same as hsctl_bmc_creds in _lib.sh) and hand them to
# Ansible as hsctl_local_secrets, which bootstrap-mgmt.yml and the cluster-secrets role use in
# place of their own Infisical login when hsctl_local is set. CI is unaffected — those tasks
# still run their normal OIDC login there. A playbook outside this pair that needs Infisical
# locally must add its own hsctl_local-aware fallback the same way before `hsctl run` can help
# it — this module doesn't know its secret paths, so it just runs it and lets any Infisical
# lookup inside fail on its own.

_run_bootstrap_playbooks=(bootstrap-mgmt bootstrap-cluster)

run_usage() {
    echo "Usage: hsctl run <playbook> [--cluster <name>] [--remote]"
    echo ""
    echo "<playbook> is any filename (without .yml) under infra/ansible/playbooks/, e.g.:"
    echo "  bootstrap-mgmt      bootstrap the mgmt-class cluster"
    echo "  bootstrap-cluster   bootstrap workload clusters (all, or one via --cluster)"
    echo ""
    echo "Options:"
    echo "  --cluster <name>    passed through as -e target=<name>; meaningful for"
    echo "                      bootstrap-cluster (its Omni cluster ID, e.g. boa1-prod)"
    echo "  --remote            dispatch the Deploy workflow's Ansible job on GitHub Actions"
    echo "                      instead of running locally, and stream its logs"
    exit 1
}

# Fetch a secrets folder from Infisical via the caller's already-authenticated CLI session,
# retrying once through an interactive login if the session is invalid/expired.
# Usage: _run_infisical_secrets <path>   -> flat JSON object {KEY: value, ...} on stdout
_run_infisical_secrets() {
    local path="$1" raw
    if ! raw=$(infisical export --silent --env=prod --path="$path" --format=json </dev/null); then
        hsctl_infisical_login || { hsctl_log_error "infisical login failed"; return 1; }
        if ! raw=$(infisical export --silent --env=prod --path="$path" --format=json </dev/null); then
            hsctl_log_error "failed to fetch secrets from Infisical (path $path)"
            return 1
        fi
    fi
    jq 'map({(.key): .value}) | add // {}' <<< "$raw"
}

# Run bootstrap-mgmt or bootstrap-cluster locally, pre-fetching the secrets they'd otherwise
# get via CI's OIDC login (see the module-level comment) and handing them to Ansible as
# hsctl_local_secrets.
_run_bootstrap_local() {
    local playbook="$1" cluster="$2"

    command -v infisical &>/dev/null || { echo "hsctl run: the infisical CLI is required (brew install infisical)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    [[ -n "$cluster" && "$playbook" == "bootstrap-mgmt" ]] && hsctl_log_info "--cluster is ignored for bootstrap-mgmt"

    hsctl_log_info "fetching secrets from Infisical via local CLI session"
    local argocd_secrets infisical_op_secrets github_actions_secrets='{}'
    argocd_secrets=$(_run_infisical_secrets /k8s/argocd/deploy-key) || exit 1
    infisical_op_secrets=$(_run_infisical_secrets /k8s/infisical) || exit 1
    [[ "$playbook" == "bootstrap-mgmt" ]] && { github_actions_secrets=$(_run_infisical_secrets /github-actions) || exit 1; }

    local extra_vars_file
    extra_vars_file=$(mktemp)
    chmod 600 "$extra_vars_file"
    # shellcheck disable=SC2064 # extra_vars_file is fixed at trap-set time, not re-evaluated later
    trap "rm -f '$extra_vars_file'" EXIT

    jq -n \
        --argjson argocd "$argocd_secrets" \
        --argjson infisical_op "$infisical_op_secrets" \
        --argjson github_actions "$github_actions_secrets" \
        '{hsctl_local: true, hsctl_local_secrets: {argocd_deploy_key: $argocd, infisical_operator: $infisical_op, github_actions: $github_actions}}' \
        > "$extra_vars_file"

    (
        cd "$HSCTL_REPO_ROOT/infra/ansible" || exit 1

        case "$playbook" in
            bootstrap-mgmt)
                hsctl_log_action "running bootstrap-mgmt.yml"
                ansible-playbook playbooks/bootstrap-mgmt.yml -e cluster_name=mgmt --extra-vars "@$extra_vars_file"
                ;;
            bootstrap-cluster)
                hsctl_log_action "running bootstrap-cluster.yml${cluster:+ (target: $cluster)}"
                if [[ -n "$cluster" ]]; then
                    ansible-playbook playbooks/bootstrap-cluster.yml -e target="$cluster" --extra-vars "@$extra_vars_file"
                else
                    ansible-playbook playbooks/bootstrap-cluster.yml --extra-vars "@$extra_vars_file"
                fi
                ;;
        esac
    )
}

# Run any other playbook locally, as-is — no local secrets handling (see module comment).
_run_generic_local() {
    local playbook="$1" cluster="$2"
    local playbook_file="$HSCTL_REPO_ROOT/infra/ansible/playbooks/$playbook.yml"

    [[ -f "$playbook_file" ]] || { hsctl_log_error "no such playbook: infra/ansible/playbooks/$playbook.yml"; exit 1; }

    (
        cd "$HSCTL_REPO_ROOT/infra/ansible" || exit 1
        hsctl_log_action "running $playbook.yml${cluster:+ (target: $cluster)}"
        if [[ -n "$cluster" ]]; then
            ansible-playbook "playbooks/$playbook.yml" -e target="$cluster"
        else
            ansible-playbook "playbooks/$playbook.yml"
        fi
    )
}

_run_local() {
    local playbook="$1" cluster="$2"

    command -v ansible-playbook &>/dev/null || { echo "hsctl run: ansible-playbook is required (pip install ansible)" >&2; exit 1; }

    if [[ " ${_run_bootstrap_playbooks[*]} " == *" $playbook "* ]]; then
        _run_bootstrap_local "$playbook" "$cluster"
    else
        _run_generic_local "$playbook" "$cluster"
    fi
}

_run_remote() {
    local playbook="$1" cluster="$2" repo="HomeScaleCloud/homescale"

    command -v gh &>/dev/null || { echo "hsctl run: the gh CLI is required (brew install gh)" >&2; exit 1; }

    local fields=(-f "playbook=$playbook")
    [[ -n "$cluster" ]] && fields+=(-f "cluster=$cluster")

    hsctl_log_action "dispatching deploy.yaml (playbook=$playbook${cluster:+, cluster=$cluster}) on $repo"
    gh workflow run deploy.yaml --repo "$repo" --ref main "${fields[@]}"

    hsctl_log_info "waiting for the run to appear..."
    local run_id="" attempt
    for attempt in $(seq 1 10); do
        sleep 2
        run_id=$(gh run list --repo "$repo" --workflow=deploy.yaml --limit 1 \
            --json databaseId,event --jq '.[] | select(.event=="workflow_dispatch") | .databaseId' 2>/dev/null) || true
        [[ -n "$run_id" ]] && break
    done

    if [[ -z "$run_id" ]]; then
        hsctl_log_error "could not find the dispatched run — check: gh run list --repo $repo --workflow=deploy.yaml"
        exit 1
    fi

    hsctl_log_success "run started: $(gh run view "$run_id" --repo "$repo" --json url --jq .url)"
    gh run watch "$run_id" --repo "$repo" --exit-status
}

run_main() {
    local playbook="" cluster="" remote=false playbook_set=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster) cluster="${2:-}"; [[ -z "$cluster" ]] && run_usage; shift 2 ;;
            --remote) remote=true; shift ;;
            -h|--help) run_usage ;;
            --*) echo "hsctl run: unknown flag '$1'" >&2; run_usage ;;
            *)
                [[ "$playbook_set" == true ]] && { echo "hsctl run: unexpected argument '$1'" >&2; run_usage; }
                playbook="$1"; playbook_set=true; shift ;;
        esac
    done

    [[ -z "$playbook" ]] && { echo "hsctl run: a playbook name is required" >&2; run_usage; }

    if [[ "$remote" == true ]]; then
        _run_remote "$playbook" "$cluster"
    else
        _run_local "$playbook" "$cluster"
    fi
}
