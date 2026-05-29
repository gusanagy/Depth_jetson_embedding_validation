#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_power_mode_once.sh [options] [-- <command> [args...]]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --label NAME            Required report label
  --mode ID|NAME          Required mode to run
  --cooldown-sec N        Delay after mode change. Default: 5
  --skip-set-mode         Assume the board is already in the requested mode
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
LABEL=""
MODE_TOKEN=""
COOLDOWN_SEC=5
SKIP_SET_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --mode) MODE_TOKEN=$2; shift 2 ;;
    --cooldown-sec) COOLDOWN_SEC=$2; shift 2 ;;
    --skip-set-mode) SKIP_SET_MODE=1; shift ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$LABEL" || -z "$MODE_TOKEN" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REPORT_ROOT="$WORKSPACE_ROOT/reports/tegrastats/$LABEL"
PLAN_PATH="$REPORT_ROOT/plan.json"

mkdir -p "$REPORT_ROOT"

declare -A MODE_NAMES
MODE_LIST=$(bash "$SCRIPT_DIR/list_power_modes.sh")
while IFS=$'\t' read -r id name; do
  MODE_NAMES["$id"]="$name"
done <<<"$MODE_LIST"

if [[ ${#MODE_NAMES[@]} -eq 0 ]]; then
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
  for id in "${!MODE_NAMES[@]}"; do
    if [[ "${MODE_NAMES[$id]}" == "$token" ]]; then
      printf '%s\n' "$id"
      return
    fi
  done
  return 1
}

if ! MODE_ID=$(resolve_mode_id "$MODE_TOKEN"); then
  echo "Unknown power mode: $MODE_TOKEN" >&2
  exit 1
fi
MODE_NAME=${MODE_NAMES[$MODE_ID]}
SAFE_NAME=$(echo "${MODE_ID}_${MODE_NAME}" | tr '[:space:]/' '__')
OUT_DIR="$REPORT_ROOT/$SAFE_NAME"
mkdir -p "$OUT_DIR"

update_plan_status() {
  local status=$1
  local note=${2:-}
  [[ -f "$PLAN_PATH" ]] || return 0
  python3 - "$PLAN_PATH" "$MODE_ID" "$status" "$OUT_DIR" "$note" <<'PY'
import json
import sys
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1])
mode_id = sys.argv[2]
status = sys.argv[3]
out_dir = sys.argv[4]
note = sys.argv[5] or None

data = json.loads(path.read_text())
for mode in data.get("modes", []):
    if mode.get("id") == mode_id:
        mode["status"] = status
        mode["result_dir"] = out_dir
        mode["updated_at"] = datetime.now().astimezone().isoformat()
        if note:
            mode.setdefault("notes", []).append(note)
        break
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

if [[ $# -eq 0 ]]; then
  if [[ ! -f "$PLAN_PATH" ]]; then
    echo "No command provided and plan not found: $PLAN_PATH" >&2
    exit 1
  fi
  mapfile -t COMMAND < <(python3 - <<PY
import json
data = json.load(open("$PLAN_PATH"))
for item in data["command"]:
    print(item)
PY
)
else
  COMMAND=("$@")
fi

if [[ $SKIP_SET_MODE -eq 1 ]]; then
  IFS=$'\t' read -r CURRENT_ID CURRENT_NAME < <(bash "$SCRIPT_DIR/get_current_power_mode.sh")
  if [[ "$CURRENT_ID" != "$MODE_ID" ]]; then
    echo "Current mode is $CURRENT_ID ($CURRENT_NAME), expected $MODE_ID ($MODE_NAME)." >&2
    echo "Reboot into the requested mode or rerun without --skip-set-mode." >&2
    update_plan_status "pending_reboot_required" "Current mode mismatch after reboot attempt."
    exit 1
  fi
else
  set +e
  bash "$SCRIPT_DIR/set_power_mode.sh" "$MODE_ID"
  status=$?
  set -e
  if [[ $status -eq 42 ]]; then
    update_plan_status "pending_reboot_required" "This mode requires reboot on this Jetson."
    exit 42
  fi
  if [[ $status -ne 0 ]]; then
    update_plan_status "failed" "set_power_mode.sh failed with status $status."
    exit "$status"
  fi
  sleep "$COOLDOWN_SEC"
fi

if [[ -f "$PLAN_PATH" ]]; then
  python3 - <<PY
import json
data = json.load(open("$PLAN_PATH"))
flops = data.get("flops_json")
if flops:
    print(flops)
PY
else
  true
fi | {
  read -r FLOPS_PATH || true
  if [[ -n "${FLOPS_PATH:-}" && -f "$FLOPS_PATH" ]]; then
    cp "$FLOPS_PATH" "$OUT_DIR/flops.json"
  fi
}

set +e
bash "$REPO_ROOT/scripts/benchmark/run_with_tegrastats.sh" "$OUT_DIR" -- "${COMMAND[@]}"
RUN_STATUS=$?
set -e

if [[ $RUN_STATUS -ne 0 ]]; then
  update_plan_status "failed" "Command failed with status $RUN_STATUS."
  exit "$RUN_STATUS"
fi

python3 "$REPO_ROOT/scripts/benchmark/summarize_tegrastats.py" \
  "$OUT_DIR/tegrastats.log" \
  --output "$OUT_DIR/tegrastats_summary.json"

python3 - <<PY
from pathlib import Path
import json
path = Path("$OUT_DIR/tegrastats_summary.json")
data = json.loads(path.read_text())
data["power_mode_id"] = "$MODE_ID"
data["power_mode_name"] = "$MODE_NAME"

run_meta_path = Path("$OUT_DIR/run_meta.json")
if run_meta_path.exists():
    run_meta = json.loads(run_meta_path.read_text())
    duration_s = run_meta.get("duration_s")
    data["duration_s"] = duration_s
    data["energy_joules"] = data.get("energy_j")
    if duration_s and data.get("energy_j") is not None:
        data["avg_power_w"] = round(data["energy_j"] / duration_s, 6)
    primary_power_max_mw = data.get("primary_power_max_mw")
    if primary_power_max_mw is not None:
        data["peak_power_w"] = round(primary_power_max_mw / 1000.0, 6)

flops_path = Path("$OUT_DIR/flops.json")
if flops_path.exists():
    flops_data = json.loads(flops_path.read_text())
    total_gflops = flops_data.get("gflops")
    if total_gflops is None and flops_data.get("flops") is not None:
        total_gflops = flops_data["flops"] / 1e9
    if total_gflops is not None:
        data["gflops"] = round(total_gflops, 6)
        if data.get("energy_j") is not None and total_gflops:
            data["jgflops"] = round(data["energy_j"] / total_gflops, 6)

path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

update_plan_status "completed" "Mode benchmark finished successfully."
echo "Result directory: $OUT_DIR"
