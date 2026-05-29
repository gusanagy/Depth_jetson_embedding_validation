#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  resume_power_mode_plan.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --label NAME            Required report label
  --cooldown-sec N        Delay after mode change. Default: 5
  --skip-set-mode         Use the current board mode for the first pending reboot-required step
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
LABEL=""
COOLDOWN_SEC=5
SKIP_SET_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --cooldown-sec) COOLDOWN_SEC=$2; shift 2 ;;
    --skip-set-mode) SKIP_SET_MODE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$LABEL" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPORT_ROOT="$WORKSPACE_ROOT/reports/tegrastats/$LABEL"
PLAN_PATH="$REPORT_ROOT/plan.json"

if [[ ! -f "$PLAN_PATH" ]]; then
  echo "Plan not found: $PLAN_PATH" >&2
  exit 1
fi

first_skip=$SKIP_SET_MODE

while true; do
  next=$(python3 - <<PY
import json
data = json.load(open("$PLAN_PATH"))
modes = data.get("modes", [])
pending_reboot = [m for m in modes if m.get("status") == "pending_reboot_required"]
pending = [m for m in modes if m.get("status") == "pending"]
if pending_reboot:
    m = pending_reboot[0]
    print(f"{m['id']}\t{m['name']}\tpending_reboot_required")
elif pending:
    m = pending[0]
    print(f"{m['id']}\t{m['name']}\tpending")
PY
)

  if [[ -z "$next" ]]; then
    python3 "$SCRIPT_DIR/summarize_power_mode_results.py" --workspace-root "$WORKSPACE_ROOT" --label "$LABEL"
    echo "Plan finished. Consolidated summary saved under: $REPORT_ROOT"
    exit 0
  fi

  IFS=$'\t' read -r mode_id mode_name mode_status <<<"$next"
  extra_args=()
  if [[ "$mode_status" == "pending_reboot_required" ]]; then
    if [[ $first_skip -ne 1 ]]; then
      echo "Mode $mode_id ($mode_name) still requires reboot." >&2
      echo "After rebooting in that mode, rerun:" >&2
      echo "  bash scripts/jetson/resume_power_mode_plan.sh --label $LABEL --skip-set-mode" >&2
      exit 42
    fi
    extra_args+=(--skip-set-mode)
  fi

  set +e
  bash "$SCRIPT_DIR/run_power_mode_once.sh" \
    --workspace-root "$WORKSPACE_ROOT" \
    --label "$LABEL" \
    --mode "$mode_id" \
    --cooldown-sec "$COOLDOWN_SEC" \
    "${extra_args[@]}"
  status=$?
  set -e

  first_skip=0

  if [[ $status -eq 42 ]]; then
    echo "Reboot required before continuing plan $LABEL." >&2
    exit 42
  fi
  if [[ $status -ne 0 ]]; then
    exit "$status"
  fi
done
