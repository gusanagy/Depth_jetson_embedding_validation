#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_depth_anything_v3_flops.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset NAME          Dataset name. Default: val_suim
  --dataset-root PATH     Optional dataset root override
  --model-name NAME       Default: da3-large
  --model-ref REF         Optional local checkpoint dir or HF repo id
  --process-res N         Default: 504
  --output-json PATH      Required output flops.json path
  --image IMAGE           Default: depth-jetson-mono:thor-jp71
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="val_suim"
DATASET_ROOT=""
MODEL_NAME="da3-large"
MODEL_REF=""
PROCESS_RES=504
OUTPUT_JSON=""
IMAGE="depth-jetson-mono:thor-jp71"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --model-name) MODEL_NAME=$2; shift 2 ;;
    --model-ref) MODEL_REF=$2; shift 2 ;;
    --process-res) PROCESS_RES=$2; shift 2 ;;
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

MODEL_ROOT="$WORKSPACE_ROOT/external_models/depth-anything-3"
CACHE_ROOT="$WORKSPACE_ROOT/cache/depth_anything_v3"

if [[ -z "$DATASET_ROOT" ]]; then
  if [[ -d "$MODEL_ROOT/datasets" ]]; then
    DATASET_ROOT="$MODEL_ROOT/datasets"
  else
    DATASET_ROOT="$WORKSPACE_ROOT/external_models/Depth-Anything-V2/datasets"
  fi
fi

if sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo -n docker)
else
  DOCKER=(docker)
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

to_container_model_ref() {
  local ref=$1
  if [[ -z "$ref" ]]; then
    return 1
  fi
  if [[ "$ref" == "$MODEL_ROOT"* ]]; then
    printf '/workspace/model/%s\n' "${ref#$MODEL_ROOT/}"
    return 0
  fi
  if [[ "$ref" == /* ]]; then
    echo "Model ref must be inside $MODEL_ROOT or be a Hugging Face repo id: $ref" >&2
    exit 1
  fi
  printf '%s\n' "$ref"
}

dataset_dir="$DATASET_ROOT/$DATASET"
input_dir="$(resolve_image_dir "$dataset_dir")"
mapfile -t input_images < <(find "$input_dir" -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' \) | sort)
input_image="${input_images[0]:-}"
if [[ -z "$input_image" ]]; then
  echo "No input image found for dataset: $dataset_dir" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_JSON")" "$CACHE_ROOT/huggingface" "$CACHE_ROOT/torch"

resolved_model_ref=""
if [[ -n "$MODEL_REF" ]]; then
  resolved_model_ref=$(to_container_model_ref "$MODEL_REF")
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
  bash -lc "export HF_HOME=/workspace/cache/huggingface TORCH_HOME=/workspace/cache/torch PYTHONPATH=/workspace/model/src:\$PYTHONPATH && python3 /workspace/runner/scripts/jetson/da3_flops_probe.py --model-root /workspace/model --input-image /workspace/input/$(basename "$input_image") --output-json /workspace/output/$(basename "$OUTPUT_JSON") --model-name \"$MODEL_NAME\" ${resolved_model_ref:+--model-ref \"$resolved_model_ref\"} --process-res \"$PROCESS_RES\""
