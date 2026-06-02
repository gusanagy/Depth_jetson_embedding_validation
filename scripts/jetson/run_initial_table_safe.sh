#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_initial_table_safe.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --label NAME            Default: initial_table_safe
  --profile NAME          quick or full. Default: full
  --da2-encoder NAME      Default: vitb
  --thermal-max-temp-c N  Default: 82
  --cooldown-sec N        Default: 120

This wrapper runs the initial table in two safer phases:
1. energy/inference with thermal cutoff and cooldown, but without auto-FLOPs
2. FLOPs probes one by one, also guarded by tegrastats and cooldown
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
LABEL="initial_table_safe"
PROFILE="full"
DA2_ENCODER="vitb"
THERMAL_MAX_TEMP_C=82
COOLDOWN_SEC=120

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --profile) PROFILE=$2; shift 2 ;;
    --da2-encoder) DA2_ENCODER=$2; shift 2 ;;
    --thermal-max-temp-c) THERMAL_MAX_TEMP_C=$2; shift 2 ;;
    --cooldown-sec) COOLDOWN_SEC=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if ! [[ "$THERMAL_MAX_TEMP_C" =~ ^[0-9]+$ ]]; then
  echo "Invalid thermal-max-temp-c: $THERMAL_MAX_TEMP_C" >&2
  exit 1
fi

if ! [[ "$COOLDOWN_SEC" =~ ^[0-9]+$ ]]; then
  echo "Invalid cooldown-sec: $COOLDOWN_SEC" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REPORT_ROOT="$WORKSPACE_ROOT/reports/initial_table/$LABEL"

cooldown_if_needed() {
  local reason=$1
  if (( COOLDOWN_SEC <= 0 )); then
    return 0
  fi
  echo "Cooldown: aguardando ${COOLDOWN_SEC}s (${reason})"
  sleep "$COOLDOWN_SEC"
}

model_completed() {
  local model_key=$1
  local run_meta="$REPORT_ROOT/$model_key/run_meta.json"
  if [[ ! -f "$run_meta" ]]; then
    return 1
  fi
  python3 - "$run_meta" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
raise SystemExit(0 if data.get("exit_code") == 0 else 1)
PY
}

run_flops_guarded() {
  local model_key=$1
  shift
  local report_dir="$REPORT_ROOT/$model_key"
  local guard_dir="$report_dir/flops_guard"
  mkdir -p "$guard_dir"

  if ! model_completed "$model_key"; then
    echo "Pulando FLOPs de $model_key porque a etapa de energia/inferencia nao concluiu com sucesso."
    return 0
  fi

  rm -f "$report_dir/flops.json" "$guard_dir/thermal_event.json"
  THERMAL_MAX_TEMP_C="$THERMAL_MAX_TEMP_C" \
    bash "$REPO_ROOT/scripts/benchmark/run_with_tegrastats.sh" "$guard_dir" -- "$@"
}

echo "== Fase 1/3: energia e inferencia com protecao termica =="
bash "$SCRIPT_DIR/run_initial_table_current_mode.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  --label "$LABEL" \
  --profile "$PROFILE" \
  --da2-encoder "$DA2_ENCODER" \
  --cooldown-sec "$COOLDOWN_SEC" \
  --thermal-max-temp-c "$THERMAL_MAX_TEMP_C" \
  --skip-flops

echo "== Fase 2/3: FLOPs guardados =="

run_flops_guarded depth_anything_v2 \
  bash "$SCRIPT_DIR/run_depth_anything_v2_flops.sh" \
    --workspace-root "$WORKSPACE_ROOT" \
    --dataset val_suim \
    --encoder "$DA2_ENCODER" \
    --output-json "$REPORT_ROOT/depth_anything_v2/flops.json"
cooldown_if_needed "apos FLOPs de depth_anything_v2"

run_flops_guarded foundation_stereo \
  bash "$SCRIPT_DIR/run_foundation_stereo_flops.sh" \
    --workspace-root "$WORKSPACE_ROOT" \
    --output-json "$REPORT_ROOT/foundation_stereo/flops.json"
cooldown_if_needed "apos FLOPs de foundation_stereo"

run_flops_guarded depth_anything_v3 \
  bash "$SCRIPT_DIR/run_depth_anything_v3_flops.sh" \
    --workspace-root "$WORKSPACE_ROOT" \
    --dataset val_suim \
    --output-json "$REPORT_ROOT/depth_anything_v3/flops.json"
cooldown_if_needed "apos FLOPs de depth_anything_v3"

run_flops_guarded depth_pro \
  bash "$SCRIPT_DIR/run_depth_pro_flops.sh" \
    --workspace-root "$WORKSPACE_ROOT" \
    --dataset val_suim \
    --output-json "$REPORT_ROOT/depth_pro/flops.json"
cooldown_if_needed "apos FLOPs de depth_pro"

run_flops_guarded marigold \
  bash "$SCRIPT_DIR/run_marigold_flops.sh" \
    --workspace-root "$WORKSPACE_ROOT" \
    --dataset val_suim \
    --output-json "$REPORT_ROOT/marigold/flops.json"
cooldown_if_needed "apos FLOPs de marigold"

run_flops_guarded igev \
  bash "$SCRIPT_DIR/run_igev_flops.sh" \
    --workspace-root "$WORKSPACE_ROOT" \
    --output-json "$REPORT_ROOT/igev/flops.json"
cooldown_if_needed "apos FLOPs de igev"

echo "== Fase 3/3: finalizacao do relatorio =="
bash "$SCRIPT_DIR/finalize_initial_table_report.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  --label "$LABEL"

echo "Relatorio seguro finalizado em: $REPORT_ROOT"
