#!/usr/bin/env bash
# Plans/applies the shared infra/terraform workspace (state in Terraform Cloud, one
# workspace for everything) via automatron instead of CI.
#
# args (ARGS_JSON): cluster (optional) - scopes the run to just that cluster's resources.
# Computed from an *untargeted* plan's own JSON output, not `terraform state list` (which
# would miss a not-yet-created resource, e.g. a brand new cluster's first tunnel).
#
# DRY_RUN=true stops after planning (deploy.yaml's PR-time Plan step) and prints the
# rendered Tailnet ACL JSON in a marker block for CI to extract and upload as an artifact,
# matching what the old direct-on-runner Plan step used to produce.
set -euo pipefail

# Matches hsctl_log's own format (hsctl.d/_lib.sh) so a human streaming this via
# `hsctl run terraform` sees one consistent style end to end, not a mix of timestamped
# client-side lines and bare echo from inside the pod.
log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${*:2}" >&2; }

repo_root="${REPO_DIR:-.}"
dry_run="${DRY_RUN:-false}"
[[ -z "${ARGS_JSON:-}" ]] && ARGS_JSON="{}"
cluster=$(jq -r '.cluster // ""' <<<"$ARGS_JSON")

# Universal auth as the "ci" identity (same one CI's OIDC path uses, now also carrying a
# universal auth method — see providers.tf) rather than the k8s Infisical Operator's own
# identity: the operator identity is deliberately low-privileged (project member, plus a
# narrow org identity-reader role) for its actual job of syncing secrets, and using it for
# terraform's own admin-level operations (managing identities/org roles) hit a bootstrap
# chicken-and-egg it can never grant itself. Creds symlinked from /ci into /k8s/automatron.
export TF_VAR_infisical_auth_method="universal"
export TF_VAR_infisical_universal_auth_client_id="${INFISICAL_CI_CLIENT_ID:-}"
export TF_VAR_infisical_universal_auth_client_secret="${INFISICAL_CI_CLIENT_SECRET:-}"
export TF_VAR_infisical_org_id="${INFISICAL_ORG_ID:-}"
export TF_VAR_infisical_github_actions=""

# REPO_DIR is mounted read-only (deliberate — every other JobTemplate here is a read-only
# ansible/script checkout), but terraform needs to write its own .terraform/ dir, provider
# cache, and possibly .terraform.lock.hcl — confirmed live, `terraform init` fails outright
# with "mkdir .terraform: read-only file system" otherwise. Copy the whole checkout into a
# writable scratch dir rather than just infra/terraform on its own: the .tf files' own
# relative paths (../../clusters, ../../../../apps — see modules/tailscale/tags.tf and
# friends) need the same directory structure around them to still resolve correctly. The
# tracked checkout is a few MB, so this is cheap.
work_root=$(mktemp -d)
cp -r "$repo_root/." "$work_root/"
repo_root="$work_root"

cd "$repo_root/infra/terraform"

# Locking (only one terraform run at a time, scheduled or ad hoc) is handled generically by
# entrypoint.sh before this script ever runs — see its own comment, and this JobTemplate's
# `locking: true` (infra/automatron/job-templates/terraform.yaml). Not redundant with
# Terraform Cloud's own state lock — TFC's only hard-fails a concurrent run outright, this
# makes scheduled and ad hoc runs queue instead.

# --- Plan (always full/untargeted first) ---
terraform init -input=false
terraform plan -input=false -out=/tmp/tfplan-full

target_args=()
if [[ -n "$cluster" ]]; then
    # FQDNs this cluster's exposePublic apps use — cloudflare_dns_record/
    # cloudflare_zero_trust_access_application are keyed by fqdn, not cluster name, so
    # matching on the resource address alone (like the other per-cluster resources below)
    # would miss them.
    fqdns=()
    for f in "$repo_root"/apps/*/app.yaml; do
        [[ -f "$f" ]] || continue
        while IFS= read -r fqdn; do
            [[ -n "$fqdn" ]] && fqdns+=("$fqdn")
        done < <(yq -o json "$f" | jq -r --arg c "$cluster" '.exposePublic[]? | select(.cluster == $c) | .fqdn')
    done
    fqdns_json=$(printf '%s\n' "${fqdns[@]:-}" | jq -R 'select(length > 0)' | jq -s '.')

    terraform show -json /tmp/tfplan-full > /tmp/tfplan-full.json
    while IFS= read -r addr; do
        [[ -n "$addr" ]] && target_args+=("-target=$addr")
    done < <(jq -r --arg cluster "$cluster" --argjson fqdns "$fqdns_json" '
        .resource_changes[]
        | select(
            (.address | test("\\[\"" + $cluster + "\"\\]$")) or
            (.address | test("\\[\"" + $cluster + "/")) or
            (.index as $i | $fqdns | any(. == $i))
          )
        | .address
    ' /tmp/tfplan-full.json)

    if [[ ${#target_args[@]} -eq 0 ]]; then
        log INFO "no resources for cluster '$cluster' in the plan — nothing to do"
        exit 0
    fi
    log INFO "scoping to ${#target_args[@]} resource(s) for cluster '$cluster'"
    terraform plan -input=false "${target_args[@]}" -out=/tmp/tfplan
else
    cp /tmp/tfplan-full /tmp/tfplan
fi

terraform show -no-color /tmp/tfplan

if [[ "$dry_run" == "true" ]]; then
    acl=$(terraform show -json /tmp/tfplan | jq -r '
        .resource_changes[]? | select(.address == "module.tailscale.tailscale_acl.this") | .change.after.acl // empty')
    if [[ -n "$acl" ]]; then
        echo "=== BEGIN ACL_JSON ==="
        echo "$acl" | jq -c '.'
        echo "=== END ACL_JSON ==="
    fi
    exit 0
fi

terraform apply -input=false -auto-approve /tmp/tfplan
