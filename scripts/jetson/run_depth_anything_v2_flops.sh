#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_depth_anything_v2_flops.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset NAME          Dataset name. Default: val_suim
  --dataset-root PATH     Optional dataset root override
  --encoder NAME          One of: vits, vitb, vitl. Default: vitb
  --input-size N          Default: 518
  --output-json PATH      Required output flops.json path
  --image IMAGE           Default: depth-jetson-mono:thor-jp71
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="val_suim"
DATASET_ROOT=""
ENCODER="vitb"
INPUT_SIZE=518
OUTPUT_JSON=""
IMAGE="depth-jetson-mono:thor-jp71"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --encoder) ENCODER=$2; shift 2 ;;
    --input-size) INPUT_SIZE=$2; shift 2 ;;
    --output-json) OUTPUT_JSON=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT_JSON" ]]; then
  echo "--output-json is required" >&2
  exit 1
fi

MODEL_ROOT="$WORKSPACE_ROOT/external_models/Depth-Anything-V2"
if [[ -z "$DATASET_ROOT" ]]; then
  DATASET_ROOT="$MODEL_ROOT/datasets"
fi

resolve_image_dir() {
  local base=$1
  local candidate
  local first_image=""

  first_image=$(find "$base" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' \) \
    -print -quit 2>/dev/null || true)
  if [[ -n "$first_image" ]]; then
    printf '%s\n' "$base"
    return 0
  fi

  for candidate in rgb images image input imgs; do
    first_image=$(find "$base/$candidate" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' \) \
      -print -quit 2>/dev/null || true)
    if [[ -d "$base/$candidate" && -n "$first_image" ]]; then
      printf '%s\n' "$base/$candidate"
      return 0
    fi
  done

  return 1
}

if sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo -n docker)
else
  DOCKER=(docker)
fi

dataset_dir="$DATASET_ROOT/$DATASET"
input_dir="$(resolve_image_dir "$dataset_dir")"
mapfile -t input_images < <(find "$input_dir" -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' \) | sort)
input_image="${input_images[0]:-}"
if [[ -z "$input_image" ]]; then
  echo "No input image found in $input_dir" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUTPUT_JSON")"

"${DOCKER[@]}" run --rm --runtime=nvidia \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -v "$MODEL_ROOT":/workspace/model \
  -v "$input_dir":/workspace/input:ro \
  -v "$(dirname "$OUTPUT_JSON")":/workspace/output \
  -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
  "$IMAGE" \
  bash -lc "cd /workspace/model && python3 /workspace/runner/scripts/jetson/da2_flops_probe.py --model-root /workspace/model --input-image /workspace/input/$(basename "$input_image") --output-json /workspace/output/$(basename "$OUTPUT_JSON") --encoder \"$ENCODER\" --input-size \"$INPUT_SIZE\""
