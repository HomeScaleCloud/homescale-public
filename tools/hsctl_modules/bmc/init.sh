#!/usr/bin/env bash
set -eo pipefail

log_info()    { echo -e "🔍 $*"; }
log_warn()    { echo -e "🚨 $*"; }
log_success() { echo -e "✅ $*"; }

bmc_init() {
  # 1) Find nodes missing BMC
  log_info "Discovering BMCs for nodes with missing BMCs..."
  local all nodes missing count
  all=$(hsctl get nodes -o json)
  missing=$(jq '[.[] | select(.bmc=="UNKNOWN_BMC")]' <<<"$all")
  count=$(jq length <<<"$missing")
  if [[ $count -eq 0 ]]; then
    log_success "No unknown BMCs"
    return 0
  fi
  log_warn "Found $count node(s) with missing BMCs"

  # Take the first one
  local node_id node_name
  node_id=$(jq -r '.[0].id'  <<<"$missing")
  node_name=$(jq -r '.[0].node'<<<"$missing")

  # 2) Scan subnet for port 443
  local subnet="10.1.240.0/24" candidates
  log_info "Scanning $subnet for Redfish BMCs (port 443)..."
  candidates=$(nmap -p443 --open -n -oG - "$subnet" |
               awk '/443\/open/ {print $2}')
  if [[ -z "$candidates" ]]; then
    log_warn "No Redfish candidates on $subnet"
    return 1
  fi

  # 3) Probe each candidate until we get node's UUID
  log_info "Probing Redfish endpoints..."
  local matched_ip matched_vendor matched_user matched_pass raw uuid

  for ip in $candidates; do
    for vendor in dell supermicro; do
      if [[ $vendor == dell ]]; then
        matched_user=root; matched_pass=calvin
      else
        matched_user=ADMIN; matched_pass=ADMIN
      fi

      raw=$(curl -ksu "$matched_user:$matched_pass" -m5 \
            "https://$ip/redfish/v1/Systems/System.Embedded.1" 2>/dev/null)
      uuid=$(jq -r '.UUID // empty' <<<"$raw" 2>/dev/null || echo "")

      if [[ "$uuid" == "$node_id" ]]; then
        matched_ip="$ip"
        matched_vendor="$vendor"
        break 2
      fi
    done
  done

  if [[ -z "$matched_ip" ]]; then
    log_warn "No BMC matching $node_id ($node_name) found"
    return 1
  fi
  log_info "Matched $node_id ($node_name) → BMC $matched_ip (vendor=$matched_vendor)"

  # 4) Create new admin credentials
  local create_uri disable_uri new_user new_pass
  new_user=admin
  new_pass=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)

  if [[ $matched_vendor == dell ]]; then
    create_uri="https://$matched_ip/redfish/v1/Managers/iDRAC.Embedded.1/Accounts/10"
    disable_uri="https://$matched_ip/redfish/v1/Managers/iDRAC.Embedded.1/Accounts/2"
  else
    create_uri="https://$matched_ip/redfish/v1/AccountService/Accounts"
    disable_uri=""
  fi

  curl -k -u "${matched_user}:${matched_pass}" -X PATCH "$create_uri" \
    -H 'Content-Type: application/json' \
    -d "{\"UserName\":\"$new_user\",\"Password\":\"$new_pass\",\"RoleId\":\"Administrator\",\"Enabled\":true}" \
    >/dev/null

  # 5) Test new creds
  if curl -ksu "$new_user:$new_pass" \
       "https://$matched_ip/redfish/v1/Systems/System.Embedded.1" \
       | jq -e .UUID >/dev/null; then

    log_success "Admin creds OK on $matched_ip — saving to 1Password"
    local item="BMC-$node_id"

    # 6) Write to 1Password
    if op item get "$item" >/dev/null 2>&1; then
      op item edit "$item" \
        password="$new_pass" \
        url="https://$matched_ip" \
        --vault bmc
    else
      op item create \
        --vault bmc \
        --category login \
        --title "$item" \
        username="$new_user" \
        password="$new_pass" \
        url="https://$matched_ip"
    fi
    log_success "Stored in 1Password as $item"

    # 7) Disable default creds
    if [[ -n "$disable_uri" ]]; then
      log_info "Disabling default creds on $matched_ip"
      curl -k -u "${matched_user}:${matched_pass}" -X PATCH "$disable_uri" \
        -H 'Content-Type: application/json' \
        -d '{"Enabled":false}' >/dev/null
      log_success "Disabled default vendor creds"
    fi

    log_success "Finished configuring $node_id ($node_name)"
  else
    log_warn "Admin-creds test failed on $matched_ip — aborting"
    return 1
  fi
}

export -f bmc_init
