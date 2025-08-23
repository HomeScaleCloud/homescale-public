get_nodes() {
  # Get useful information about HomeScale nodes/Omni machines in useful formats.
  set -euo pipefail

  LABEL_FILTER=""
  OUTPUT_FORMAT="table"
  SEARCH_TERM=""
  SCRIPT_NAME=$(basename "$0")

  print_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  -l, --labels     Filter by label(s), e.g., platform=metal,cluster=manor
  -o, --output     Output format: table (default), json, yaml
  --search         Search by machine UUID or node name
  -h, --help       Show this help message
EOF
  }

  check_op_logged_in() {
    SESSION_FILE="$HOME/.config/hsctl/op_session"

    # Use cached session if available
    if [[ -f "$SESSION_FILE" ]]; then
      export OP_SESSION_my="$(cat "$SESSION_FILE")"
    fi

    # If not signed in, do so and cache session
    if ! op whoami &>/dev/null; then
      echo "🔐 Signing in to 1Password..."
      mkdir -p "$(dirname "$SESSION_FILE")"
      SESSION_TOKEN=$(op signin --raw)

      if [[ -z "$SESSION_TOKEN" ]]; then
        echo "❌ Failed to sign in to 1Password." >&2
        exit 1
      fi

      echo "$SESSION_TOKEN" > "$SESSION_FILE"
      chmod 600 "$SESSION_FILE"
      export OP_SESSION_my="$SESSION_TOKEN"
    fi
  }

  get_bmc_ip_from_op() {
    local uuid="$1"
    local item="BMC-$uuid"
    local result

    if result=$(op item get "$item" --vault bmc --format json 2>/dev/null); then
      echo "$result" | jq -r '.urls[0].href // empty' | sed -E 's#^https://([^/]+)/?#\1#'
    else
      echo "UNKNOWN_BMC"
    fi
  }

  # Parse args
  while [[ $# -gt 0 ]]; do
    case $1 in
      -l|--labels)
        LABEL_FILTER="$2"
        shift 2
        ;;
      -o|--output)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --search)
        SEARCH_TERM="$2"
        shift 2
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  raw_json=$(omnictl get machinestatus -o json)

  flat_json=$(echo "$raw_json" | jq '
    .items // [.] | map({
      id: .metadata.id,
      node: (.spec.network.hostname // "unknown"),
      infra: (.metadata.labels["omni.sidero.dev/infra-provider-id"] // "unknown"),
      zone: (
        (.metadata.labels | to_entries | map(select(.key|test("/zone$"))) | .[0].value) // "unknown"
      ),
      region: (
        (.metadata.labels | to_entries | map(select(.key|test("/region$"))) | .[0].value) // "unknown"
      ),
      bmc: "PLACEHOLDER_BMC",
      cluster: (.spec.cluster // "unknown"),
      platform: (.metadata.labels["omni.sidero.dev/platform"] // "unknown"),
      version: (.spec.talosversion // "unknown")
    })')

  # ✅ Ensure 1Password is logged in
  check_op_logged_in

  # Replace bmc placeholder with real IPs from 1Password
  flat_json=$(echo "$flat_json" | jq -c '.[]' | while read -r machine; do
    uuid=$(echo "$machine" | jq -r '.id')
    bmc_ip=$(get_bmc_ip_from_op "$uuid")
    echo "$machine" | jq --arg bmc "$bmc_ip" '.bmc = $bmc'
  done | jq -s '.')

  # Apply filters
  filtered_json="$flat_json"

  if [[ -n "$LABEL_FILTER" ]]; then
    jq_filter=".[]"
    IFS=',' read -ra filters <<< "$LABEL_FILTER"
    for filter in "${filters[@]}"; do
      key="${filter%%=*}"
      val="${filter#*=}"
      jq_filter+=" | select(.$key == \"$val\")"
    done
    filtered_json=$(echo "$flat_json" | jq -c "[ $jq_filter ]")
  fi

  if [[ -n "$SEARCH_TERM" ]]; then
    filtered_json=$(echo "$flat_json" | jq -c "[ .[] | select(.id == \"$SEARCH_TERM\" or .node == \"$SEARCH_TERM\") ]")
  fi

  # Output
  case "$OUTPUT_FORMAT" in
    json)
      echo "$filtered_json" | jq .
      ;;
    yaml)
      if command -v yq &>/dev/null; then
        echo "$filtered_json" | yq -y
      else
        echo "yq not found. Please install Python yq (https://github.com/kislyuk/yq) for YAML output." >&2
        exit 1
      fi
      ;;
    table)
      printf "%-36s %-20s %-14s %-8s %-8s %-18s %-10s %-10s %-8s\n" \
        "MACHINE-ID" "NODE" "INFRA" "ZONE" "REGION" "BMC-ADDRESS" "CLUSTER" "PLATFORM" "VERSION"
      echo "$filtered_json" |
        jq -r '.[] | [
          .id,
          .node,
          .infra,
          .zone,
          .region,
          .bmc,
          .cluster,
          .platform,
          .version
        ] | @tsv' |
        awk -F'\t' '{ printf "%-36s %-20s %-14s %-8s %-8s %-18s %-10s %-10s %-8s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9 }'
      ;;
    *)
      echo "Unknown output format: $OUTPUT_FORMAT" >&2
      exit 1
      ;;
  esac
}
