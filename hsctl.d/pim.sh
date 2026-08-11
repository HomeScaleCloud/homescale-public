#!/usr/bin/env bash

pim_usage() {
    echo "Usage: hsctl pim [command] [args...]"
    echo ""
    echo "No command: interactive full-screen UI (role/group only)."
    echo "Read-only listing: 'hsctl get pimrole|pimgroup|pimazurerole|pimapproval'."
    echo ""
    echo "Commands:"
    echo "  activate <role|group|azure> <name|id> --reason \"<justification>\""
    echo "           [--duration <e.g. 2h35m, 45m, or ISO8601 — default 8h>] [--access member|owner] [--scope <arm-scope>]"
    echo "                                    --access: group only. --scope: azure only, required."
    echo ""
    echo "  deactivate <role|group|azure> <name|id> [--scope <arm-scope>]"
    echo ""
    echo "  cancel <role|group> <request-id>"
    echo "                                    Withdraw your own pending request. IDs from 'hsctl get pimapprovals'."
    echo ""
    echo "  approve <role|group|azure> <approval-id> [--deny] [--reason \"...\"] [--scope <arm-scope>]"
    echo "                                    approval-id from 'hsctl get pimapprovals -o json'. Prompts for confirmation."
    echo ""
    echo "  logout"
    echo "                                    Clear the cached Graph sign-in (Keychain)."
    exit 1
}

source "$HSCTL_ROOT/hsctl.d/get.sh"

_pim_parse_duration() {
    local input="$1"
    [[ "$input" =~ ^PT ]] && { printf '%s\n' "$input"; return 0; }
    if [[ -z "$input" || ! "$input" =~ ^([0-9]+h)?([0-9]+m)?([0-9]+s)?$ ]]; then
        hsctl_log_error "invalid --duration '$input' (expected e.g. 2h35m, 45m, 1h30m, or ISO8601 like PT2H35M)"
        return 1
    fi
    local h m s iso="PT"
    h=$(grep -o '[0-9]*h' <<< "$input" | tr -d 'h')
    m=$(grep -o '[0-9]*m' <<< "$input" | tr -d 'm')
    s=$(grep -o '[0-9]*s' <<< "$input" | tr -d 's')
    if [[ -z "$h$m$s" ]]; then
        hsctl_log_error "invalid --duration '$input' (expected e.g. 2h35m, 45m, 1h30m, or ISO8601 like PT2H35M)"
        return 1
    fi
    [[ -n "$h" ]] && iso+="${h}H"
    [[ -n "$m" ]] && iso+="${m}M"
    [[ -n "$s" ]] && iso+="${s}S"
    printf '%s\n' "$iso"
}

_pim_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_pim_new_guid() { uuidgen | tr '[:upper:]' '[:lower:]'; }

_pim_is_guid() {
    [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

_pim_jwt_claim() {
    local token="$1" claim="$2" payload
    payload=$(cut -d. -f2 <<< "$token" | tr '_-' '/+')
    case $(( ${#payload} % 4 )) in
        2) payload+="==" ;;
        3) payload+="=" ;;
    esac
    base64 -d <<< "$payload" 2>/dev/null | jq -r --arg c "$claim" '.[$c] // empty'
}

_pim_my_id_graph() {
    if [[ -z "${HSCTL_PIM_MY_ID_GRAPH:-}" ]]; then
        local token; token=$(_pim_graph_access_token) || return 1
        HSCTL_PIM_MY_ID_GRAPH=$(_pim_jwt_claim "$token" oid)
        [[ -z "$HSCTL_PIM_MY_ID_GRAPH" ]] && { hsctl_log_error "could not resolve your identity from the Graph sign-in"; return 1; }
        export HSCTL_PIM_MY_ID_GRAPH
    fi
    printf '%s\n' "$HSCTL_PIM_MY_ID_GRAPH"
}

_pim_my_id_arm() {
    if [[ -z "${HSCTL_PIM_MY_ID_ARM:-}" ]]; then
        _pim_ensure_signed_in || return 1
        HSCTL_PIM_MY_ID_ARM=$(az ad signed-in-user show --query id -o tsv 2>/dev/null) || true
        [[ -z "$HSCTL_PIM_MY_ID_ARM" ]] && { hsctl_log_error "could not resolve your signed-in identity"; return 1; }
        export HSCTL_PIM_MY_ID_ARM
    fi
    printf '%s\n' "$HSCTL_PIM_MY_ID_ARM"
}

_pim_resolve_role_def_id() {
    local name="$1"
    _pim_is_guid "$name" && { printf '%s\n' "$name"; return 0; }
    local resp id
    resp=$(_pim_graph_rest GET "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?\$filter=$(_pim_urlencode "displayName eq '$name'")") || return 1
    id=$(jq -r '.value[0].id // empty' <<< "$resp")
    [[ -z "$id" ]] && { hsctl_log_error "no directory role found matching '$name'"; return 1; }
    printf '%s\n' "$id"
}

_pim_resolve_group_id() {
    local name="$1" endpoint="$2"
    _pim_is_guid "$name" && { printf '%s\n' "$name"; return 0; }
    local resp id
    resp=$(_pim_graph_rest GET "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/${endpoint}/filterByCurrentUser(on='principal')?\$expand=group") || return 1
    id=$(jq -r --arg n "$name" '[.value[] | select(.group.displayName == $n)][0].group.id // empty' <<< "$resp")
    [[ -z "$id" ]] && { hsctl_log_error "no group found matching '$name' among your $([[ "$endpoint" == eligibilityScheduleInstances ]] && echo eligible || echo active) group PIM assignments"; return 1; }
    printf '%s\n' "$id"
}

_pim_resolve_azure_role_def_id() {
    local name="$1" scope="$2"
    _pim_is_guid "$name" && { printf '%s/providers/Microsoft.Authorization/roleDefinitions/%s\n' "$scope" "$name"; return 0; }
    local resp id
    resp=$(_pim_rest GET "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&\$filter=$(_pim_urlencode "roleName eq '$name'")") || return 1
    id=$(jq -r '.value[0].id // empty' <<< "$resp")
    [[ -z "$id" ]] && { hsctl_log_error "no Azure role definition found matching '$name' at scope $scope"; return 1; }
    printf '%s\n' "$id"
}

_pim_activate_role() {
    local name="$1" reason="$2" duration="$3"
    local my_id; my_id=$(_pim_my_id_graph) || exit 1
    local role_id; role_id=$(_pim_resolve_role_def_id "$name") || exit 1
    hsctl_log_action "activating directory role '$name' for $duration"
    local body resp
    body=$(jq -n --arg pid "$my_id" --arg rid "$role_id" --arg just "$reason" --arg dur "$duration" --arg start "$(_pim_now_iso)" '{
        action: "selfActivate", principalId: $pid, roleDefinitionId: $rid, directoryScopeId: "/",
        justification: $just, scheduleInfo: {startDateTime: $start, expiration: {type: "afterDuration", duration: $dur}}
    }')
    resp=$(_pim_graph_rest POST "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests" "$body") || exit 1
    hsctl_log_success "role '$name' activation request $(jq -r '.id' <<< "$resp"): $(jq -r '.status // "submitted"' <<< "$resp")"
}

_pim_deactivate_role() {
    local name="$1"
    local my_id; my_id=$(_pim_my_id_graph) || exit 1
    local role_id; role_id=$(_pim_resolve_role_def_id "$name") || exit 1
    hsctl_log_action "deactivating directory role '$name'"
    local body resp
    body=$(jq -n --arg pid "$my_id" --arg rid "$role_id" '{action: "selfDeactivate", principalId: $pid, roleDefinitionId: $rid, directoryScopeId: "/"}')
    resp=$(_pim_graph_rest POST "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests" "$body") || exit 1
    hsctl_log_success "role '$name' deactivation request: $(jq -r '.status // "submitted"' <<< "$resp")"
}

_pim_activate_group() {
    local name="$1" reason="$2" duration="$3" access="$4"
    local my_id; my_id=$(_pim_my_id_graph) || exit 1
    local group_id; group_id=$(_pim_resolve_group_id "$name" eligibilityScheduleInstances) || exit 1
    hsctl_log_action "activating '$access' access on group '$name' for $duration"
    local body resp
    body=$(jq -n --arg pid "$my_id" --arg gid "$group_id" --arg acc "$access" --arg just "$reason" --arg dur "$duration" --arg start "$(_pim_now_iso)" '{
        action: "selfActivate", principalId: $pid, groupId: $gid, accessId: $acc,
        justification: $just, scheduleInfo: {startDateTime: $start, expiration: {type: "afterDuration", duration: $dur}}
    }')
    resp=$(_pim_graph_rest POST "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests" "$body") || exit 1
    hsctl_log_success "group '$name' activation request $(jq -r '.id' <<< "$resp"): $(jq -r '.status // "submitted"' <<< "$resp")"
}

_pim_deactivate_group() {
    local name="$1" access="${2:-member}"
    local my_id; my_id=$(_pim_my_id_graph) || exit 1
    local group_id; group_id=$(_pim_resolve_group_id "$name" assignmentScheduleInstances) || exit 1
    hsctl_log_action "deactivating '$access' access on group '$name'"
    local body resp
    body=$(jq -n --arg pid "$my_id" --arg gid "$group_id" --arg acc "$access" '{action: "selfDeactivate", principalId: $pid, groupId: $gid, accessId: $acc}')
    resp=$(_pim_graph_rest POST "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests" "$body") || exit 1
    hsctl_log_success "group '$name' deactivation request: $(jq -r '.status // "submitted"' <<< "$resp")"
}

_pim_activate_azure() {
    local name="$1" reason="$2" duration="$3" scope="$4"
    local my_id; my_id=$(_pim_my_id_arm) || exit 1
    local role_id; role_id=$(_pim_resolve_azure_role_def_id "$name" "$scope") || exit 1

    local elig_resp elig_id
    elig_resp=$(_pim_rest GET "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01-preview&\$filter=asTarget()") || exit 1
    elig_id=$(jq -r --arg rid "$role_id" '[.value[] | select(.properties.roleDefinitionId == $rid)][0].properties.roleEligibilityScheduleId // empty' <<< "$elig_resp")
    [[ -z "$elig_id" ]] && { hsctl_log_error "no eligible Azure role assignment found for '$name' at scope $scope"; exit 1; }

    local guid; guid=$(_pim_new_guid)
    hsctl_log_action "activating Azure role '$name' at $scope for $duration"
    local body resp
    body=$(jq -n --arg pid "$my_id" --arg rid "$role_id" --arg just "$reason" --arg dur "$duration" --arg start "$(_pim_now_iso)" --arg elig "$elig_id" '{
        properties: {
            principalId: $pid, roleDefinitionId: $rid, requestType: "SelfActivate",
            linkedRoleEligibilityScheduleId: $elig, justification: $just,
            scheduleInfo: {startDateTime: $start, expiration: {type: "AfterDuration", duration: $dur}}
        }
    }')
    resp=$(_pim_rest PUT "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/${guid}?api-version=2020-10-01-preview" "$body") || exit 1
    hsctl_log_success "Azure role '$name' activation request: $(jq -r '.properties.status // "submitted"' <<< "$resp")"
}

_pim_deactivate_azure() {
    local name="$1" scope="$2"
    local my_id; my_id=$(_pim_my_id_arm) || exit 1
    local role_id; role_id=$(_pim_resolve_azure_role_def_id "$name" "$scope") || exit 1

    local active_resp assign_id
    active_resp=$(_pim_rest GET "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01-preview&\$filter=asTarget()") || exit 1
    assign_id=$(jq -r --arg rid "$role_id" '[.value[] | select(.properties.roleDefinitionId == $rid)][0].properties.roleAssignmentScheduleId // empty' <<< "$active_resp")
    [[ -z "$assign_id" ]] && { hsctl_log_error "no active Azure role assignment found for '$name' at scope $scope"; exit 1; }

    local guid; guid=$(_pim_new_guid)
    hsctl_log_action "deactivating Azure role '$name' at $scope"
    local body resp
    body=$(jq -n --arg pid "$my_id" --arg rid "$role_id" --arg linked "$assign_id" '{
        properties: {principalId: $pid, roleDefinitionId: $rid, requestType: "SelfDeactivate", linkedRoleAssignmentScheduleId: $linked}
    }')
    resp=$(_pim_rest PUT "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/${guid}?api-version=2020-10-01-preview" "$body") || exit 1
    hsctl_log_success "Azure role '$name' deactivation request: $(jq -r '.properties.status // "submitted"' <<< "$resp")"
}

pim_activate() {
    local type="${1:-}"; shift || true
    [[ -z "$type" ]] && { echo "Usage: hsctl pim activate <role|group|azure> <name|id> --reason \"...\" [flags]" >&2; exit 1; }

    local name="" reason="" duration="8h" access="member" scope=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="$2"; shift 2 ;;
            --duration) duration="$2"; shift 2 ;;
            --access) access="$2"; shift 2 ;;
            --scope) scope="$2"; shift 2 ;;
            *)
                if [[ -z "$name" ]]; then name="$1"; else echo "hsctl pim activate: unexpected arg '$1'" >&2; exit 1; fi
                shift
                ;;
        esac
    done
    [[ -z "$name" ]] && { echo "Usage: hsctl pim activate <role|group|azure> <name|id> --reason \"...\" [flags]" >&2; exit 1; }
    [[ -z "$reason" ]] && { echo "hsctl pim activate: --reason is required (PIM requires a justification)" >&2; exit 1; }
    duration=$(_pim_parse_duration "$duration") || exit 1

    case "$type" in
        role|roles) _pim_activate_role "$name" "$reason" "$duration" ;;
        group|groups) _pim_activate_group "$name" "$reason" "$duration" "$access" ;;
        azure)
            [[ -z "$scope" ]] && { echo "hsctl pim activate azure: --scope is required" >&2; exit 1; }
            _pim_activate_azure "$name" "$reason" "$duration" "$(_pim_normalize_scope "$scope")"
            ;;
        *) echo "hsctl pim activate: unknown type '$type' (expected role, group, or azure)" >&2; exit 1 ;;
    esac
}

pim_deactivate() {
    local type="${1:-}"; shift || true
    [[ -z "$type" ]] && { echo "Usage: hsctl pim deactivate <role|group|azure> <name|id> [--scope <arm-scope>]" >&2; exit 1; }

    local name="" access="member" scope=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --access) access="$2"; shift 2 ;;
            --scope) scope="$2"; shift 2 ;;
            *)
                if [[ -z "$name" ]]; then name="$1"; else echo "hsctl pim deactivate: unexpected arg '$1'" >&2; exit 1; fi
                shift
                ;;
        esac
    done
    [[ -z "$name" ]] && { echo "Usage: hsctl pim deactivate <role|group|azure> <name|id> [--scope <arm-scope>]" >&2; exit 1; }

    case "$type" in
        role|roles) _pim_deactivate_role "$name" ;;
        group|groups) _pim_deactivate_group "$name" "$access" ;;
        azure)
            [[ -z "$scope" ]] && { echo "hsctl pim deactivate azure: --scope is required" >&2; exit 1; }
            _pim_deactivate_azure "$name" "$(_pim_normalize_scope "$scope")"
            ;;
        *) echo "hsctl pim deactivate: unknown type '$type' (expected role, group, or azure)" >&2; exit 1 ;;
    esac
}

_pim_cancel_role() {
    local id="$1"
    hsctl_log_action "canceling role assignment request $id"
    _pim_graph_rest POST "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests/${id}/cancel" '{}' >/dev/null || exit 1
    hsctl_log_success "role assignment request $id canceled"
}

_pim_cancel_group() {
    local id="$1"
    hsctl_log_action "canceling group assignment request $id"
    _pim_graph_rest POST "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/${id}/cancel" '{}' >/dev/null || exit 1
    hsctl_log_success "group assignment request $id canceled"
}

pim_cancel() {
    local type="${1:-}" id="${2:-}"
    [[ -z "$type" || -z "$id" ]] && { echo "Usage: hsctl pim cancel <role|group> <request-id>" >&2; exit 1; }
    case "$type" in
        role|roles) _pim_cancel_role "$id" ;;
        group|groups) _pim_cancel_group "$id" ;;
        *) echo "hsctl pim cancel: unknown type '$type' (expected role or group)" >&2; exit 1 ;;
    esac
}

_pim_resolve_pending_step_graph() {
    local get_url="$1" resp step_id
    resp=$(_pim_graph_rest GET "$get_url") || return 1
    step_id=$(jq -r '([.steps[]? | select(.assignedToMe == true and .status == "InProgress")] + [.steps[]? | select(.status == "InProgress")])[0].id // empty' <<< "$resp")
    [[ -z "$step_id" ]] && { hsctl_log_error "no in-progress approval step found at $get_url — it may already be decided"; return 1; }
    printf '%s\n' "$step_id"
}

# roleAssignmentApprovals/assignmentApprovals only exist under Graph's beta segment, unlike the rest of this
# file's v1.0 endpoints. The approval object's id is always the same as the id of the request that needed approval.
_pim_decide_role() {
    local approval_id="$1" result="$2" reason="$3"
    local base="https://graph.microsoft.com/beta/roleManagement/directory/roleAssignmentApprovals/${approval_id}"
    local step_id; step_id=$(_pim_resolve_pending_step_graph "$base") || exit 1
    local body resp
    body=$(jq -n --arg r "$result" --arg j "$reason" '{reviewResult: $r, justification: $j}')
    resp=$(_pim_graph_rest PATCH "${base}/steps/${step_id}" "$body") || exit 1
    hsctl_log_success "$result recorded for role approval $approval_id"
}

_pim_decide_group() {
    local approval_id="$1" result="$2" reason="$3"
    local base="https://graph.microsoft.com/beta/identityGovernance/privilegedAccess/group/assignmentApprovals/${approval_id}"
    local step_id; step_id=$(_pim_resolve_pending_step_graph "$base") || exit 1
    local body resp
    body=$(jq -n --arg r "$result" --arg j "$reason" '{reviewResult: $r, justification: $j}')
    resp=$(_pim_graph_rest PATCH "${base}/steps/${step_id}" "$body") || exit 1
    hsctl_log_success "$result recorded for group approval $approval_id"
}

# ARM's approval object id is likewise the same as the id of the roleAssignmentScheduleRequest.
_pim_decide_azure() {
    local scope="$1" approval_id="$2" result="$3" reason="$4"
    local base="https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignmentApprovals/${approval_id}"
    local resp stage_path stage_id
    resp=$(_pim_rest GET "${base}?api-version=2021-01-01-preview") || exit 1
    stage_path=$(jq -r '([.properties.stages[]? | select(.properties.assignedToMe == true and .properties.status == "InProgress")] + [.properties.stages[]? | select(.properties.status == "InProgress")])[0].id // empty' <<< "$resp")
    [[ -z "$stage_path" ]] && { hsctl_log_error "no in-progress approval stage found for Azure approval $approval_id — it may already be decided"; exit 1; }
    stage_id="${stage_path##*/}"
    local body resp2
    body=$(jq -n --arg r "$result" --arg j "$reason" '{properties: {reviewResult: $r, justification: $j}}')
    resp2=$(_pim_rest PATCH "${base}/stages/${stage_id}?api-version=2021-01-01-preview" "$body") || exit 1
    hsctl_log_success "$result recorded for Azure approval $approval_id"
}

pim_approve() {
    local type="${1:-}"; shift || true
    [[ -z "$type" ]] && { echo "Usage: hsctl pim approve <role|group|azure> <approval-id> [--deny] [--reason \"...\"] [--scope <arm-scope>]" >&2; exit 1; }

    local approval_id="" deny=false reason="" scope=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deny) deny=true; shift ;;
            --reason) reason="$2"; shift 2 ;;
            --scope) scope="$2"; shift 2 ;;
            *)
                if [[ -z "$approval_id" ]]; then approval_id="$1"
                else echo "hsctl pim approve: unexpected arg '$1'" >&2; exit 1
                fi
                shift
                ;;
        esac
    done
    [[ -z "$approval_id" ]] && { echo "Usage: hsctl pim approve <role|group|azure> <approval-id> [--deny] [--reason \"...\"]" >&2; exit 1; }

    local result="Approve"; [[ "$deny" == true ]] && result="Deny"

    echo "About to $result approval $approval_id (type $type) — this affects someone else's access." >&2
    [[ -n "$reason" ]] && echo "Reason: $reason" >&2
    local confirm
    read -r -p "Continue? [y/N] " confirm </dev/tty
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted." >&2; exit 1; }

    case "$type" in
        role|roles) _pim_decide_role "$approval_id" "$result" "$reason" ;;
        group|groups) _pim_decide_group "$approval_id" "$result" "$reason" ;;
        azure)
            [[ -z "$scope" ]] && { echo "hsctl pim approve azure: --scope is required" >&2; exit 1; }
            _pim_decide_azure "$(_pim_normalize_scope "$scope")" "$approval_id" "$result" "$reason"
            ;;
        *) echo "hsctl pim approve: unknown type '$type'" >&2; exit 1 ;;
    esac
}

_pim_ui_rows() {
    local pending; pending=$(_pim_urlencode "status eq 'PendingApproval'")
    local f_role_elig f_role_active f_group_elig f_group_active
    local f_role_appr f_role_mine f_group_appr f_group_mine
    f_role_elig=$(mktemp); f_role_active=$(mktemp); f_group_elig=$(mktemp); f_group_active=$(mktemp)
    f_role_appr=$(mktemp); f_role_mine=$(mktemp); f_group_appr=$(mktemp); f_group_mine=$(mktemp)

    _pim_fetch_parallel \
        "$f_role_elig" "https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances/filterByCurrentUser(on='principal')?\$expand=roleDefinition" \
        "$f_role_active" "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')?\$expand=roleDefinition" \
        "$f_group_elig" "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances/filterByCurrentUser(on='principal')?\$expand=group" \
        "$f_group_active" "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleInstances/filterByCurrentUser(on='principal')?\$expand=group" \
        "$f_role_appr" "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='approver')?\$filter=${pending}&\$expand=principal" \
        "$f_role_mine" "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='principal')?\$filter=${pending}&\$expand=principal" \
        "$f_group_appr" "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/filterByCurrentUser(on='approver')?\$filter=${pending}&\$expand=principal" \
        "$f_group_mine" "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/filterByCurrentUser(on='principal')?\$filter=${pending}&\$expand=principal" \
        || { rm -f "$f_role_elig" "$f_role_active" "$f_group_elig" "$f_group_active" "$f_role_appr" "$f_role_mine" "$f_group_appr" "$f_group_mine"; return 1; }

    local role_elig role_active group_elig group_active role_appr role_mine group_appr group_mine
    role_elig=$(<"$f_role_elig"); role_active=$(<"$f_role_active")
    group_elig=$(<"$f_group_elig"); group_active=$(<"$f_group_active")
    role_appr=$(<"$f_role_appr"); role_mine=$(<"$f_role_mine")
    group_appr=$(<"$f_group_appr"); group_mine=$(<"$f_group_mine")
    rm -f "$f_role_elig" "$f_role_active" "$f_group_elig" "$f_group_active" "$f_role_appr" "$f_role_mine" "$f_group_appr" "$f_group_mine"

    local role_pending group_pending
    role_pending=$(jq -n --argjson a "$(jq '.value' <<< "$role_appr")" --argjson m "$(jq '.value' <<< "$role_mine")" \
        '($a | map(. + {role:"approver"})) + ($m | map(. + {role:"requestor"}))')
    group_pending=$(jq -n --argjson a "$(jq '.value' <<< "$group_appr")" --argjson m "$(jq '.value' <<< "$group_mine")" \
        '($a | map(. + {role:"approver"})) + ($m | map(. + {role:"requestor"}))')

    local role_names group_names
    role_names=$(jq -n --argjson e "$role_elig" --argjson a "$role_active" '($e.value + $a.value) | map({(.roleDefinitionId): .roleDefinition.displayName}) | add // {}')
    group_names=$(jq -n --argjson e "$group_elig" --argjson a "$group_active" '($e.value + $a.value) | map({(.groupId): .group.displayName}) | add // {}')

    local sep=$'\x1f'
    {
        jq -r --arg sep "$sep" '.value[] | [.roleDefinition.displayName, "role", "eligible", (.endDateTime // "permanent"), "", "", ""] | join($sep)' <<< "$role_elig"
        jq -r --arg sep "$sep" '.value[] | [.roleDefinition.displayName, "role", "active", (.endDateTime // "permanent"), "", "", ""] | join($sep)' <<< "$role_active"
        jq -r --arg sep "$sep" '.value[] | [.group.displayName, "group", "eligible", (.endDateTime // "permanent"), .accessId, "", ""] | join($sep)' <<< "$group_elig"
        jq -r --arg sep "$sep" '.value[] | [.group.displayName, "group", "active", (.endDateTime // "permanent"), .accessId, "", ""] | join($sep)' <<< "$group_active"
        jq -r --arg sep "$sep" --argjson names "$role_names" '
            .[] | [($names[.roleDefinitionId] // .roleDefinitionId), "role", ("pending-" + .role), (.justification // "-"), "", .id,
                   ((.principal.displayName // "-") + " <" + (.principal.userPrincipalName // .principal.mail // "-") + ">")] | join($sep)' <<< "$role_pending"
        jq -r --arg sep "$sep" --argjson names "$group_names" '
            .[] | [($names[.groupId] // .groupId), "group", ("pending-" + .role), (.justification // "-"), "", .id,
                   ((.principal.displayName // "-") + " <" + (.principal.userPrincipalName // .principal.mail // "-") + ">")] | join($sep)' <<< "$group_pending"
    }
}

_pim_status_label() {
    case "$1" in
        pending-approver)  printf '%s\n' "pending · needs your approval" ;;
        pending-requestor) printf '%s\n' "pending · sent by you" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

_pim_ui_act_on() {
    local type="$1" status="$2" name="$3" access="$4" reqid="$5" requester="$6"
    local actions=()
    case "$status" in
        eligible) actions=("Activate") ;;
        active) actions=("Deactivate") ;;
        pending-requestor) actions=("Cancel") ;;
        pending-approver) actions=("Approve" "Deny") ;;
    esac
    actions+=("Back")

    local header="$type: $name ($(_pim_status_label "$status"))"
    [[ "$status" == pending-* ]] && header+=" — request $reqid"
    [[ -n "$requester" && "$status" == "pending-approver" ]] && header+=" — from $requester"

    local action
    action=$(printf '%s\n' "${actions[@]}" | fzf --height=40% --reverse --border --header="$header") || return 0
    [[ -z "$action" || "$action" == "Back" ]] && return 0

    case "$action" in
        Activate)
            local reason duration
            read -r -p "Reason: " reason </dev/tty
            [[ -z "$reason" ]] && { echo "Reason is required." >&2; sleep 1; return 0; }
            read -r -p "Duration [8h]: " duration </dev/tty
            duration="${duration:-8h}"
            duration=$(_pim_parse_duration "$duration") || { sleep 1; return 0; }
            if [[ "$type" == role ]]; then
                ( _pim_activate_role "$name" "$reason" "$duration" )
            else
                local acc; read -r -p "Access [member]: " acc </dev/tty; acc="${acc:-member}"
                ( _pim_activate_group "$name" "$reason" "$duration" "$acc" )
            fi
            ;;
        Deactivate)
            read -r -p "Deactivate $type '$name'? [y/N] " confirm </dev/tty
            [[ "$confirm" =~ ^[Yy]$ ]] || return 0
            if [[ "$type" == role ]]; then
                ( _pim_deactivate_role "$name" )
            else
                ( _pim_deactivate_group "$name" "${access:-member}" )
            fi
            ;;
        Approve|Deny)
            local reason
            read -r -p "Reason (optional): " reason </dev/tty
            read -r -p "$action this $type request${requester:+ from $requester}? [y/N] " confirm </dev/tty
            [[ "$confirm" =~ ^[Yy]$ ]] || return 0
            if [[ "$type" == role ]]; then
                ( _pim_decide_role "$reqid" "$action" "$reason" )
            else
                ( _pim_decide_group "$reqid" "$action" "$reason" )
            fi
            ;;
        Cancel)
            read -r -p "Withdraw this pending request? [y/N] " confirm </dev/tty
            [[ "$confirm" =~ ^[Yy]$ ]] || return 0
            if [[ "$type" == role ]]; then
                ( _pim_cancel_role "$reqid" )
            else
                ( _pim_cancel_group "$reqid" )
            fi
            ;;
    esac
    read -r -p "Press enter to continue..." _ </dev/tty
}

pim_ui() {
    command -v fzf &>/dev/null || { echo "hsctl pim: fzf is required for the interactive UI (brew install fzf)" >&2; exit 1; }
    local sep=$'\x1f'

    while true; do
        local raw rows
        raw=$(_pim_ui_rows) || return 1
        [[ -z "$raw" ]] && { echo "Nothing to show — no PIM assignments or pending requests."; return 0; }

        rows=""
        while IFS="$sep" read -r name type status detail access reqid requester; do
            local pretty; pretty=$(printf "%-7s %-30s %-24s %-28s %-36s %s" "$type" "$(_pim_status_label "$status")" "$name" "$requester" "$reqid" "$detail")
            rows+="${pretty}${sep}${type}${sep}${status}${sep}${name}${sep}${access}${sep}${reqid}${sep}${requester}"$'\n'
        done <<< "$raw"
        rows="${rows%$'\n'}"

        local header; header=$(printf "%-7s %-30s %-24s %-28s %-36s %s" "TYPE" "STATUS" "NAME" "REQUESTER" "REQUEST ID" "DETAIL")
        local selected
        selected=$(printf '%s\n' "$rows" | fzf \
            --delimiter="$sep" --with-nth=1 --no-sort \
            --height=100% --reverse --border \
            --header="${header}"$'\n↑/↓ move · enter select · esc/ctrl-c quit') || return 0
        [[ -z "$selected" ]] && return 0

        local type status name access reqid requester
        IFS="$sep" read -r _ type status name access reqid requester <<< "$selected"
        _pim_ui_act_on "$type" "$status" "$name" "$access" "$reqid" "$requester"
    done
}

pim_main() {
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) pim_usage ;;
            *) args+=("$1"); shift ;;
        esac
    done
    set -- "${args[@]+"${args[@]}"}"

    _pim_require_deps

    [[ $# -eq 0 ]] && { pim_ui; return; }

    local verb; verb="$(tr '[:upper:]' '[:lower:]' <<< "$1")"; shift
    case "$verb" in
        activate) pim_activate "$@" ;;
        deactivate) pim_deactivate "$@" ;;
        cancel) pim_cancel "$@" ;;
        approve) pim_approve "$@" ;;
        logout) _pim_graph_token_clear; echo "Graph sign-in cleared." ;;
        *) echo "hsctl pim: unknown command '$verb'" >&2; pim_usage ;;
    esac
}
