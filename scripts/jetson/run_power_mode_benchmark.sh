#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_power_mode_benchmark.sh [options] -- <command> [args...]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --modes LIST            Comma-separated mode ids or names. Default: all
  --label NAME            Report label. Default: benchmark
  --cooldown-sec N        Delay after each mode switch. Default: 5
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
MODES="all"
LABEL="benchmark"
COOLDOWN_SEC=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --modes) MODES=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --cooldown-sec) COOLDOWN_SEC=$2; shift 2 ;;
    --) shift; break ;;
    *) usage; exit 1 ;;
  esac
done

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REPORT_ROOT="$WORKSPACE_ROOT/reports/tegrastats/$LABEL"

mkdir -p "$REPORT_ROOT"

declare -a MODE_IDS
declare -A MODE_NAMES

while IFS=$'\t' read -r id name; do
  MODE_IDS+=("$id")
  MODE_NAMES["$id"]="$name"
done < <("$SCRIPT_DIR/list_power_modes.sh")

resolve_mode_id() {
  local token=$1
  if [[ "$token" =~ ^[0-9]+$ ]]; then
    echo "$token"
    return
  fi
  for id in "${MODE_IDS[@]}"; do
    if [[ "${MODE_NAMES[$id]}" == "$token" ]]; then
      echo "$id"
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
    selected_ids+=("$(resolve_mode_id "$token")")
  done
fi

for mode_id in "${selected_ids[@]}"; do
  mode_name=${MODE_NAMES[$mode_id]}
  safe_name=$(echo "${mode_id}_${mode_name}" | tr '[:space:]/' '__')
  out_dir="$REPORT_ROOT/$safe_name"

  mkdir -p "$out_dir"

  echo
  echo "== Power mode $mode_id ($mode_name) =="
  set +e
  bash "$SCRIPT_DIR/set_power_mode.sh" "$mode_id"
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 42 ]]; then
      cat >"$out_dir/skipped.json" <<EOF
{
  "power_mode_id": "$mode_id",
  "power_mode_name": "$mode_name",
  "status": "skipped_reboot_required"
}
EOF
      echo "Skipping $mode_id ($mode_name): reboot required on this Jetson."
      continue
    fi
    exit "$status"
  fi
  sleep "$COOLDOWN_SEC"

  bash "$REPO_ROOT/scripts/benchmark/run_with_tegrastats.sh" "$out_dir" -- "$@"
  python3 "$REPO_ROOT/scripts/benchmark/summarize_tegrastats.py" \
    "$out_dir/tegrastats.log" \
    --output "$out_dir/tegrastats_summary.json"

  python3 - <<PY
from pathlib import Path
import json
path = Path("$out_dir/tegrastats_summary.json")
data = json.loads(path.read_text())
data["power_mode_id"] = "$mode_id"
data["power_mode_name"] = "$mode_name"

run_meta_path = Path("$out_dir/run_meta.json")
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

flops_path = Path("$out_dir/flops.json")
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
done
