#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_marigold_flops.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset NAME          Dataset name. Default: val_suim
  --dataset-root PATH     Optional dataset root override
  --checkpoint NAME       Default: prs-eth/marigold-depth-v1-1
  --denoise-steps N       Default: 4
  --ensemble-size N       Default: 1
  --processing-res N      Default: 384
  --fp16                  Enable half precision on CUDA.
  --output-json PATH      Required output flops.json path
  --image IMAGE           Default: depth-jetson-marigold:thor-jp71
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="val_suim"
DATASET_ROOT=""
CHECKPOINT="prs-eth/marigold-depth-v1-1"
DENOISE_STEPS=4
ENSEMBLE_SIZE=1
PROCESSING_RES=384
FP16=0
OUTPUT_JSON=""
IMAGE="depth-jetson-marigold:thor-jp71"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --checkpoint) CHECKPOINT=$2; shift 2 ;;
    --denoise-steps) DENOISE_STEPS=$2; shift 2 ;;
    --ensemble-size) ENSEMBLE_SIZE=$2; shift 2 ;;
    --processing-res) PROCESSING_RES=$2; shift 2 ;;
    --fp16) FP16=1; shift ;;
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

MODEL_ROOT="$WORKSPACE_ROOT/external_models/Marigold"
if [[ -z "$DATASET_ROOT" ]]; then
  if [[ -d "$MODEL_ROOT/datasets" ]]; then
    DATASET_ROOT="$MODEL_ROOT/datasets"
  else
    DATASET_ROOT="$WORKSPACE_ROOT/external_models/Depth-Anything-V2/datasets"
  fi
fi
CACHE_ROOT="$WORKSPACE_ROOT/cache/marigold"

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
mkdir -p "$(dirname "$OUTPUT_JSON")" "$CACHE_ROOT/huggingface" "$CACHE_ROOT/torch"

fp16_arg=()
if [[ $FP16 -eq 1 ]]; then
  fp16_arg+=(--fp16)
fi

"${DOCKER[@]}" run --rm --runtime=nvidia \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -v "$MODEL_ROOT":/workspace/model \
  -v "$input_dir":/workspace/input:ro \
  -v "$(dirname "$OUTPUT_JSON")":/workspace/output \
  -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
  -v "$CACHE_ROOT/huggingface":/workspace/cache/huggingface \
  -v "$CACHE_ROOT/torch":/workspace/cache/torch \
  "$IMAGE" \
  bash -lc "export HF_HOME=/workspace/cache/huggingface TORCH_HOME=/workspace/cache/torch PYTHONPATH=/workspace/model:\$PYTHONPATH && python3 /workspace/runner/scripts/jetson/marigold_flops_probe.py --model-root /workspace/model --input-image /workspace/input/$(basename "$input_image") --output-json /workspace/output/$(basename "$OUTPUT_JSON") --checkpoint \"$CHECKPOINT\" --denoise-steps \"$DENOISE_STEPS\" --ensemble-size \"$ENSEMBLE_SIZE\" --processing-res \"$PROCESSING_RES\" ${fp16_arg[*]}"
