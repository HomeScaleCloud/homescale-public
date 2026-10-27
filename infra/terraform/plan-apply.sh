#!/usr/bin/env bash
# Plans (and, unless DRY_RUN=true, applies) the shared infra/terraform workspace (state in
# Terraform Cloud, one workspace for everything). Used directly by CI
# (.github/workflows/deploy.yaml's terraform job) and by `hsctl run terraform -e local` for
# a human bootstrapping infra (including the core cluster itself) before CI/Tailscale can
# reach anything.
#
# Env vars:
#   CLUSTER  - optional; scopes the plan/apply to just this cluster's own resources
#              (Cloudflare tunnel, DNS records, VolSync secrets, etc). Computed from an
#              *untargeted* plan's own JSON output, not `terraform state list` (which would
#              miss a not-yet-created resource, e.g. a brand new cluster's first tunnel).
#   DRY_RUN  - "true" stops after planning (default: "false")
#
# Caller is responsible for Terraform's own Infisical provider auth being already set up
# in the environment (TF_VAR_infisical_github_actions + INFISICAL_AUTH_JWT for CI's GitHub
# OIDC path, or TF_VAR_infisical_auth_method=universal + TF_VAR_infisical_universal_auth_*
# for a local run — see providers.tf and hsctl.d/run.sh).
#
# Writes the full plan to /tmp/tfplan (scoped runs also leave the untargeted plan at
# /tmp/tfplan-full) so a caller that needs the raw JSON — e.g. to extract the rendered
# Tailnet ACL — can run `terraform show -json /tmp/tfplan` against it afterward.
set -euo pipefail

cluster="${CLUSTER:-}"
dry_run="${DRY_RUN:-false}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$repo_root/infra/terraform"

terraform init -input=false
terraform plan -input=false -out=/tmp/tfplan-full

if [[ -n "$cluster" ]]; then
    # cloudflare_dns_record/cloudflare_zero_trust_access_application are keyed by FQDN, not
    # cluster name, so matching on the resource address alone (like everything else below)
    # would miss them — scan apps/*/app.yaml's own exposePublic[].cluster filter instead,
    # kept independent of any hardcoded resource-type list so it can't drift from the HCL.
    fqdns=()
    for f in "$repo_root"/apps/*/app.yaml; do
        [[ -f "$f" ]] || continue
        while IFS= read -r fqdn; do
            [[ -n "$fqdn" ]] && fqdns+=("$fqdn")
        done < <(yq -o json "$f" | jq -r --arg c "$cluster" '.exposePublic[]? | select(.cluster == $c) | .fqdn')
    done
    fqdns_json=$(printf '%s\n' "${fqdns[@]:-}" | jq -R 'select(length > 0)' | jq -s '.')

    terraform show -json /tmp/tfplan-full > /tmp/tfplan-full.json
    target_args=()
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
        echo "no resources for cluster '$cluster' in the plan — nothing to do"
        exit 0
    fi
    echo "scoping to ${#target_args[@]} resource(s) for cluster '$cluster'"
    terraform plan -input=false "${target_args[@]}" -out=/tmp/tfplan
else
    cp /tmp/tfplan-full /tmp/tfplan
fi

terraform show -no-color /tmp/tfplan

if [[ "$dry_run" == "true" ]]; then
    exit 0
fi

terraform apply -input=false -auto-approve /tmp/tfplan
