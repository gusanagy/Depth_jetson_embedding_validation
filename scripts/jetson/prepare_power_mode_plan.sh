#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  prepare_power_mode_plan.sh [options] -- <command> [args...]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --label NAME            Required report label
  --modes LIST            Comma-separated ids or names. Default: all
  --flops-json PATH       Optional flops.json to copy into each mode result dir
  --overwrite             Replace an existing plan.json
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
LABEL=""
MODES="all"
FLOPS_JSON=""
OVERWRITE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --modes) MODES=$2; shift 2 ;;
    --flops-json) FLOPS_JSON=$2; shift 2 ;;
    --overwrite) OVERWRITE=1; shift ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$LABEL" || $# -eq 0 ]]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPORT_ROOT="$WORKSPACE_ROOT/reports/tegrastats/$LABEL"
PLAN_PATH="$REPORT_ROOT/plan.json"

mkdir -p "$REPORT_ROOT"

if [[ -f "$PLAN_PATH" && $OVERWRITE -ne 1 ]]; then
  echo "Plan already exists: $PLAN_PATH" >&2
  echo "Use --overwrite to replace it or resume with resume_power_mode_plan.sh" >&2
  exit 1
fi

declare -a MODE_IDS
declare -A MODE_NAMES
MODE_LIST=$(bash "$SCRIPT_DIR/list_power_modes.sh")
while IFS=$'\t' read -r id name; do
  MODE_IDS+=("$id")
  MODE_NAMES["$id"]="$name"
done <<<"$MODE_LIST"

if [[ ${#MODE_IDS[@]} -eq 0 ]]; then
  echo "No power modes found. Check nvpmodel.conf accessibility." >&2
  exit 1
fi

resolve_mode_id() {
  local token=$1
  if [[ "$token" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$token"
    return
  fi
  local id
  for id in "${MODE_IDS[@]}"; do
    if [[ "${MODE_NAMES[$id]}" == "$token" ]]; then
      printf '%s\n' "$id"
      return
    fi
  done
  return 1
}

selected_ids=()
if [[ "$MODES" == "all" ]]; then
  selected_ids=("${MODE_IDS[@]}")
else
  IFS=',' read -r -a tokens <<<"$MODES"
  for token in "${tokens[@]}"; do
    if ! resolved_id=$(resolve_mode_id "$token"); then
      echo "Unknown power mode: $token" >&2
      exit 1
    fi
    selected_ids+=("$resolved_id")
  done
fi

if [[ -n "$FLOPS_JSON" ]]; then
  FLOPS_JSON=$(realpath "$FLOPS_JSON")
fi

COMMAND_JSON=$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "$@")
MODE_SPECS=()
for mode_id in "${selected_ids[@]}"; do
  MODE_SPECS+=("${mode_id}:${MODE_NAMES[$mode_id]}")
done

python3 - "$PLAN_PATH" "$LABEL" "$WORKSPACE_ROOT" "$REPORT_ROOT" "$FLOPS_JSON" "$COMMAND_JSON" "${MODE_SPECS[@]}" <<'PY'
import json
import sys
from datetime import datetime
from pathlib import Path

plan_path = Path(sys.argv[1])
label = sys.argv[2]
workspace_root = sys.argv[3]
report_root = sys.argv[4]
flops_json = sys.argv[5] or None
command = json.loads(sys.argv[6])
mode_specs = sys.argv[7:]

modes = []
for spec in mode_specs:
    mode_id, mode_name = spec.split(":", 1)
    modes.append(
        {
            "id": mode_id,
            "name": mode_name,
            "status": "pending",
            "result_dir": None,
            "notes": [],
        }
    )

plan = {
    "label": label,
    "workspace_root": workspace_root,
    "report_root": report_root,
    "created_at": datetime.now().astimezone().isoformat(),
    "flops_json": flops_json,
    "command": command,
    "modes": modes,
}

plan_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Plan created: $PLAN_PATH"
echo "Report root: $REPORT_ROOT"
echo
echo "Run until the next reboot-required mode:"
echo "  bash scripts/jetson/resume_power_mode_plan.sh --label $LABEL"
echo
echo "After reboot into a requested mode, continue with:"
echo "  bash scripts/jetson/resume_power_mode_plan.sh --label $LABEL --skip-set-mode"
