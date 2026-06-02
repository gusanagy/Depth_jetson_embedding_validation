#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_initial_table_current_mode.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --label NAME            Report label. Default: initial_table_current_mode
  --profile NAME          quick or full. Default: quick
  --da2-encoder NAME      Default: vitb
  --da2-limit N           Override quick limit for DA2
  --da3-limit N           Override quick limit for DA3
  --depth-pro-limit N     Override quick limit for Depth Pro
  --marigold-limit N      Override quick limit for Marigold
  --foundation-limit N    Override quick limit for FoundationStereo
  --igev-limit N          Override quick limit for IGEV
  --skip-flops            Disable automatic FLOPs probes after successful runs
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
LABEL="initial_table_current_mode"
PROFILE="quick"
DA2_ENCODER="vitb"
DA2_LIMIT=""
DA3_LIMIT=""
DEPTH_PRO_LIMIT=""
MARIGOLD_LIMIT=""
FOUNDATION_LIMIT=""
IGEV_LIMIT=""
AUTO_FLOPS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --profile) PROFILE=$2; shift 2 ;;
    --da2-encoder) DA2_ENCODER=$2; shift 2 ;;
    --da2-limit) DA2_LIMIT=$2; shift 2 ;;
    --da3-limit) DA3_LIMIT=$2; shift 2 ;;
    --depth-pro-limit) DEPTH_PRO_LIMIT=$2; shift 2 ;;
    --marigold-limit) MARIGOLD_LIMIT=$2; shift 2 ;;
    --foundation-limit) FOUNDATION_LIMIT=$2; shift 2 ;;
    --igev-limit) IGEV_LIMIT=$2; shift 2 ;;
    --skip-flops) AUTO_FLOPS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ "$PROFILE" != "quick" && "$PROFILE" != "full" ]]; then
  echo "Invalid profile: $PROFILE" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REPORT_ROOT="$WORKSPACE_ROOT/reports/initial_table/$LABEL"
SUMMARY_CSV="$REPORT_ROOT/summary.csv"
SUMMARY_JSONL="$REPORT_ROOT/summary.jsonl"
SUMMARY_JSON="$REPORT_ROOT/summary.json"
CONTEXT_JSON="$REPORT_ROOT/context.json"

mkdir -p "$REPORT_ROOT"

IFS=$'\t' read -r CURRENT_MODE_ID CURRENT_MODE_NAME < <(bash "$SCRIPT_DIR/get_current_power_mode.sh")

case "$PROFILE" in
  quick)
    DA2_LIMIT=${DA2_LIMIT:-8}
    DA3_LIMIT=${DA3_LIMIT:-8}
    DEPTH_PRO_LIMIT=${DEPTH_PRO_LIMIT:-8}
    MARIGOLD_LIMIT=${MARIGOLD_LIMIT:-4}
    FOUNDATION_LIMIT=${FOUNDATION_LIMIT:-8}
    IGEV_LIMIT=${IGEV_LIMIT:-8}
    DA2_DATASET_SCOPE="all_datasets_limit_${DA2_LIMIT}_per_dataset"
    DA3_SCOPE="all_datasets_limit_${DA3_LIMIT}_per_dataset"
    DEPTH_PRO_SCOPE="all_datasets_limit_${DEPTH_PRO_LIMIT}_per_dataset"
    MARIGOLD_SCOPE="all_datasets_limit_${MARIGOLD_LIMIT}_per_dataset"
    FOUNDATION_SCOPE="uwstereo_val_limit_${FOUNDATION_LIMIT}"
    IGEV_SCOPE="uwstereo_val_limit_${IGEV_LIMIT}"
    DA2_ARGS=(--dataset all --encoder "$DA2_ENCODER" --limit "$DA2_LIMIT")
    DA3_ARGS=(--dataset all --limit "$DA3_LIMIT")
    DEPTH_PRO_ARGS=(--dataset all --limit "$DEPTH_PRO_LIMIT")
    MARIGOLD_ARGS=(--dataset all --limit "$MARIGOLD_LIMIT" --fp16)
    FOUNDATION_ARGS=(--limit "$FOUNDATION_LIMIT")
    IGEV_ARGS=(--limit "$IGEV_LIMIT")
    ;;
  full)
    DA2_DATASET_SCOPE="all_datasets_full"
    DA3_SCOPE="all_datasets_full"
    DEPTH_PRO_SCOPE="all_datasets_full"
    MARIGOLD_SCOPE="all_datasets_full"
    FOUNDATION_SCOPE="uwstereo_val_full"
    IGEV_SCOPE="uwstereo_val_full"
    DA2_ARGS=(--dataset all --encoder "$DA2_ENCODER")
    DA3_ARGS=(--dataset all)
    DEPTH_PRO_ARGS=(--dataset all)
    MARIGOLD_ARGS=(--dataset all --fp16)
    FOUNDATION_ARGS=()
    IGEV_ARGS=()
    ;;
esac

cat >"$SUMMARY_CSV" <<'EOF'
model_key,model_name,status,power_mode_id,power_mode_name,profile,dataset_scope,duration_s,energy_joules,avg_power_w,peak_power_w,primary_power_rail,samples,artifacts_dir,report_dir,notes
EOF
: >"$SUMMARY_JSONL"

python3 - "$CONTEXT_JSON" "$LABEL" "$PROFILE" "$CURRENT_MODE_ID" "$CURRENT_MODE_NAME" "$WORKSPACE_ROOT" <<'PY'
import json
import sys
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "label": sys.argv[2],
    "profile": sys.argv[3],
    "power_mode_id": sys.argv[4],
    "power_mode_name": sys.argv[5],
    "workspace_root": sys.argv[6],
    "created_at": datetime.now().astimezone().isoformat(),
}
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

append_row() {
  local row_json=$1
  ROW_JSON="$row_json" python3 - "$SUMMARY_CSV" "$SUMMARY_JSONL" <<'PY'
import csv
import json
import os
import sys
from pathlib import Path

row = json.loads(os.environ["ROW_JSON"])
csv_path = Path(sys.argv[1])
jsonl_path = Path(sys.argv[2])
fieldnames = [
    "model_key",
    "model_name",
    "status",
    "power_mode_id",
    "power_mode_name",
    "profile",
    "dataset_scope",
    "duration_s",
    "energy_joules",
    "avg_power_w",
    "peak_power_w",
    "primary_power_rail",
    "samples",
    "artifacts_dir",
    "report_dir",
    "notes",
]
with csv_path.open("a", encoding="utf-8", newline="") as fh:
    writer = csv.DictWriter(fh, fieldnames=fieldnames)
    writer.writerow(row)
with jsonl_path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(row, sort_keys=True) + "\n")
PY
}

append_pending_row() {
  local model_key=$1
  local model_name=$2
  local notes=$3
  local row_json
  row_json=$(python3 - <<PY
import json
print(json.dumps({
    "model_key": "$model_key",
    "model_name": "$model_name",
    "status": "runner_pending",
    "power_mode_id": "$CURRENT_MODE_ID",
    "power_mode_name": "$CURRENT_MODE_NAME",
    "profile": "$PROFILE",
    "dataset_scope": None,
    "duration_s": None,
    "energy_joules": None,
    "avg_power_w": None,
    "peak_power_w": None,
    "primary_power_rail": None,
    "samples": None,
    "artifacts_dir": None,
    "report_dir": None,
    "notes": "$notes",
}))
PY
)
  append_row "$row_json"
}

append_result_row() {
  local model_key=$1
  local model_name=$2
  local status=$3
  local dataset_scope=$4
  local artifacts_dir=$5
  local report_dir=$6
  local notes=$7

  local row_json
  row_json=$(python3 - "$report_dir/tegrastats_summary.json" <<PY
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
summary = {}
if summary_path.exists():
    summary = json.loads(summary_path.read_text())
print(json.dumps({
    "model_key": "$model_key",
    "model_name": "$model_name",
    "status": "$status",
    "power_mode_id": "$CURRENT_MODE_ID",
    "power_mode_name": "$CURRENT_MODE_NAME",
    "profile": "$PROFILE",
    "dataset_scope": "$dataset_scope",
    "duration_s": summary.get("duration_s"),
    "energy_joules": summary.get("energy_joules"),
    "avg_power_w": summary.get("avg_power_w"),
    "peak_power_w": summary.get("peak_power_w"),
    "primary_power_rail": summary.get("primary_power_rail"),
    "samples": summary.get("samples"),
    "artifacts_dir": "$artifacts_dir",
    "report_dir": "$report_dir",
    "notes": "$notes",
}))
PY
)
  append_row "$row_json"
}

append_supported_row() {
  append_result_row "$1" "$2" completed "$3" "$4" "$5" "$6"
}

append_failed_row() {
  append_result_row "$1" "$2" failed "$3" "$4" "$5" "$6"
}

run_with_energy() {
  local model_key=$1
  shift
  local report_dir="$REPORT_ROOT/$model_key"
  mkdir -p "$report_dir"
  local exit_code=0
  set +e
  bash "$REPO_ROOT/scripts/benchmark/run_with_tegrastats.sh" "$report_dir" -- "$@"
  exit_code=$?
  set -e

  if [[ -f "$report_dir/tegrastats.log" ]]; then
    python3 "$REPO_ROOT/scripts/benchmark/summarize_tegrastats.py" \
      "$report_dir/tegrastats.log" \
      --output "$report_dir/tegrastats_summary.json"
  fi

  python3 - "$report_dir/tegrastats_summary.json" "$report_dir/run_meta.json" "$CURRENT_MODE_ID" "$CURRENT_MODE_NAME" "$exit_code" <<'PY'
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
run_meta_path = Path(sys.argv[2])
mode_id = sys.argv[3]
mode_name = sys.argv[4]
exit_code = int(sys.argv[5])
data = {}
if summary_path.exists():
    data = json.loads(summary_path.read_text())
data["power_mode_id"] = mode_id
data["power_mode_name"] = mode_name
data["exit_code"] = exit_code
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
summary_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  return "$exit_code"
}

maybe_run_flops_probe() {
  local model_key=$1
  local report_dir=$2
  local flops_path="$report_dir/flops.json"

  if [[ $AUTO_FLOPS -eq 0 ]]; then
    return 0
  fi

  case "$model_key" in
    depth_anything_v2)
      bash "$SCRIPT_DIR/run_depth_anything_v2_flops.sh" \
        --workspace-root "$WORKSPACE_ROOT" \
        --dataset val_suim \
        --encoder "$DA2_ENCODER" \
        --output-json "$flops_path"
      ;;
    foundation_stereo)
      bash "$SCRIPT_DIR/run_foundation_stereo_flops.sh" \
        --workspace-root "$WORKSPACE_ROOT" \
        --output-json "$flops_path"
      ;;
    depth_anything_v3)
      bash "$SCRIPT_DIR/run_depth_anything_v3_flops.sh" \
        --workspace-root "$WORKSPACE_ROOT" \
        --dataset val_suim \
        --output-json "$flops_path"
      ;;
    depth_pro)
      bash "$SCRIPT_DIR/run_depth_pro_flops.sh" \
        --workspace-root "$WORKSPACE_ROOT" \
        --dataset val_suim \
        --output-json "$flops_path"
      ;;
    marigold)
      bash "$SCRIPT_DIR/run_marigold_flops.sh" \
        --workspace-root "$WORKSPACE_ROOT" \
        --dataset val_suim \
        --output-json "$flops_path"
      ;;
    igev)
      bash "$SCRIPT_DIR/run_igev_flops.sh" \
        --workspace-root "$WORKSPACE_ROOT" \
        --output-json "$flops_path"
      ;;
  esac
}

record_model() {
  local model_key=$1
  local model_name=$2
  local dataset_scope=$3
  local artifacts_dir=$4
  local report_dir=$5
  local success_notes=$6
  local failure_notes=$7
  shift 7

  if run_with_energy "$model_key" "$@"; then
    if ! maybe_run_flops_probe "$model_key" "$report_dir"; then
      echo "Warning: FLOPs probe failed for $model_key; keeping energy results." >&2
    fi
    append_supported_row "$model_key" "$model_name" "$dataset_scope" "$artifacts_dir" "$report_dir" "$success_notes"
  else
    local exit_code=$?
    append_failed_row "$model_key" "$model_name" "$dataset_scope" "$artifacts_dir" "$report_dir" "$failure_notes (exit_code=$exit_code)"
  fi
}

echo "Current power mode: $CURRENT_MODE_ID ($CURRENT_MODE_NAME)"
echo "Report root: $REPORT_ROOT"

record_model depth_anything_v2 \
  "Depth Anything V2" \
  "$DA2_DATASET_SCOPE" \
  "$WORKSPACE_ROOT/artifacts/da2" \
  "$REPORT_ROOT/depth_anything_v2" \
  "Monocular runner ready on Jetson." \
  "Monocular runner failed on Jetson." \
  bash "$SCRIPT_DIR/run_depth_anything_v2.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  "${DA2_ARGS[@]}"

record_model foundation_stereo \
  "FoundationStereo" \
  "$FOUNDATION_SCOPE" \
  "$WORKSPACE_ROOT/artifacts/foundation_stereo" \
  "$REPORT_ROOT/foundation_stereo" \
  "Stereo runner uses UWStereo validation split." \
  "Stereo runner failed on UWStereo validation split." \
  bash "$SCRIPT_DIR/run_foundation_stereo.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  "${FOUNDATION_ARGS[@]}"

record_model depth_anything_v3 \
  "Depth Anything V3" \
  "$DA3_SCOPE" \
  "$WORKSPACE_ROOT/artifacts/da3" \
  "$REPORT_ROOT/depth_anything_v3" \
  "Monocular runner ready on Jetson." \
  "Monocular runner failed on Jetson." \
  bash "$SCRIPT_DIR/run_depth_anything_v3.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  "${DA3_ARGS[@]}"

record_model depth_pro \
  "Depth Pro" \
  "$DEPTH_PRO_SCOPE" \
  "$WORKSPACE_ROOT/artifacts/depth_pro" \
  "$REPORT_ROOT/depth_pro" \
  "Monocular runner saves raw depth, grayscale and color outputs." \
  "Monocular runner failed on Jetson." \
  bash "$SCRIPT_DIR/run_depth_pro.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  "${DEPTH_PRO_ARGS[@]}"

record_model marigold \
  "Marigold" \
  "$MARIGOLD_SCOPE" \
  "$WORKSPACE_ROOT/artifacts/marigold" \
  "$REPORT_ROOT/marigold" \
  "Diffusion-based monocular runner in dedicated container." \
  "Diffusion-based monocular runner failed on Jetson." \
  bash "$SCRIPT_DIR/run_marigold.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  "${MARIGOLD_ARGS[@]}"

record_model igev \
  "IGEV" \
  "$IGEV_SCOPE" \
  "$WORKSPACE_ROOT/artifacts/igev" \
  "$REPORT_ROOT/igev" \
  "Stereo runner uses UWStereo validation split only." \
  "Stereo runner failed on UWStereo validation split." \
  bash "$SCRIPT_DIR/run_igev.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  "${IGEV_ARGS[@]}"

python3 - "$SUMMARY_JSONL" "$SUMMARY_JSON" <<'PY'
import json
import sys
from pathlib import Path

jsonl_path = Path(sys.argv[1])
json_path = Path(sys.argv[2])
rows = [json.loads(line) for line in jsonl_path.read_text(encoding="utf-8").splitlines() if line.strip()]
json_path.write_text(json.dumps(rows, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

python3 "$SCRIPT_DIR/backfill_initial_table_report.py" \
  --report-root "$REPORT_ROOT" \
  --write-enriched-summary

echo "Summary CSV: $SUMMARY_CSV"
echo "Summary JSON: $SUMMARY_JSON"
echo "Summary enriched CSV: $REPORT_ROOT/summary_enriched.csv"
