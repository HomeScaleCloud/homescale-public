#!/usr/bin/env bash
# hsctl - HomeScale control
set -euo pipefail

REAL_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$REAL_PATH")"
MODULE_DIR="$HOME/Repos/homescale/tools/hsctl_modules"

COMMAND="${1:-}"
SUBCOMMAND="${2:-}"

# No command given
if [[ -z "$COMMAND" ]]; then
  echo "Usage: hsctl <command> [subcommand]"
  echo "Available commands:"
  find "$MODULE_DIR" -type f -name '*.sh' |
    sed -E "s|$MODULE_DIR/||; s|\.sh$||" |
    awk -F/ '{ if (NF == 2) { print "  " $1 " " $2 } else { print "  " $1 } }' |
    sort | uniq
  exit 1
fi

shift || true
[[ -n "${SUBCOMMAND:-}" ]] && shift || true

# 1. Nested command: hsctl get nodes → hsctl_modules/get/nodes.sh
CMD_PATH_NESTED="$MODULE_DIR/$COMMAND/$SUBCOMMAND.sh"
FUNC_NAME_NESTED="${COMMAND}_${SUBCOMMAND//-/_}"

# 2. Top-level command: hsctl speedtest → hsctl_modules/speedtest.sh
CMD_PATH_TOP="$MODULE_DIR/$COMMAND.sh"
FUNC_NAME_TOP="${COMMAND//-/_}"

if [[ -n "${SUBCOMMAND:-}" && -f "$CMD_PATH_NESTED" ]]; then
  source "$CMD_PATH_NESTED"
  if declare -f "$FUNC_NAME_NESTED" > /dev/null; then
    "$FUNC_NAME_NESTED" "$@"
  else
    echo "Function $FUNC_NAME_NESTED not found in $CMD_PATH_NESTED" >&2
    exit 1
  fi
elif [[ -f "$CMD_PATH_TOP" ]]; then
  source "$CMD_PATH_TOP"
  if declare -f "$FUNC_NAME_TOP" > /dev/null; then
    "$FUNC_NAME_TOP" "$@"
  else
    echo "Function $FUNC_NAME_TOP not found in $CMD_PATH_TOP" >&2
    exit 1
  fi
elif [[ "$COMMAND" == "version" ]]; then
  cat "$SCRIPT_DIR/../VERSION"
else
  echo "Unknown command: $COMMAND ${SUBCOMMAND:-}" >&2
  exit 1
fi
