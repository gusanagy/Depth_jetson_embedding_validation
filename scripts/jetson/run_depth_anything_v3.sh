#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_depth_anything_v3.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset NAME          Dataset name under the chosen dataset root. Default: all
  --dataset-root PATH     Override dataset root. Default: DA3 datasets fallback to DA2 datasets
  --model-name NAME       Default: da3-large
  --process-res N         Default: 504
  --limit N               Optional image limit.
  --image IMAGE           Docker image tag. Default: depth-jetson-mono:thor-jp71
  --no-progress           Disable tqdm progress bar.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="all"
DATASET_ROOT=""
MODEL_NAME="da3-large"
PROCESS_RES=504
LIMIT=0
IMAGE="depth-jetson-mono:thor-jp71"
SHOW_PROGRESS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --model-name) MODEL_NAME=$2; shift 2 ;;
    --process-res) PROCESS_RES=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --no-progress) SHOW_PROGRESS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

MODEL_ROOT="$WORKSPACE_ROOT/external_models/depth-anything-3"
OUTPUT_ROOT="$WORKSPACE_ROOT/artifacts/da3"
CACHE_ROOT="$WORKSPACE_ROOT/cache/depth_anything_v3"

if [[ -z "$DATASET_ROOT" ]]; then
  if [[ -d "$MODEL_ROOT/datasets" ]]; then
    DATASET_ROOT="$MODEL_ROOT/datasets"
  else
    DATASET_ROOT="$WORKSPACE_ROOT/external_models/Depth-Anything-V2/datasets"
  fi
fi

if [[ ! -d "$DATASET_ROOT" ]]; then
  echo "Dataset root missing: $DATASET_ROOT" >&2
  exit 1
fi

if sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo -n docker)
else
  DOCKER=(docker)
fi

if ! "${DOCKER[@]}" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image not found: $IMAGE" >&2
  echo "Build it with: bash scripts/jetson/build_docker_images.sh --only mono" >&2
  exit 1
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

datasets=()
if [[ "$DATASET" == "all" ]]; then
  while IFS= read -r dir; do
    datasets+=("$(basename "$dir")")
  done < <(find "$DATASET_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
else
  datasets=("$DATASET")
fi

mkdir -p "$OUTPUT_ROOT" "$CACHE_ROOT/huggingface" "$CACHE_ROOT/torch"

for ds in "${datasets[@]}"; do
  dataset_dir="$DATASET_ROOT/$ds"
  if [[ ! -d "$dataset_dir" ]]; then
    echo "Skipping missing dataset: $dataset_dir"
    continue
  fi

  if ! input_dir="$(resolve_image_dir "$dataset_dir")"; then
    echo "Skipping dataset without flat image dir: $dataset_dir" >&2
    continue
  fi

  out_dir="$OUTPUT_ROOT/$ds/$MODEL_NAME"
  mkdir -p "$out_dir"

  progress_arg=()
  if [[ $SHOW_PROGRESS -eq 0 ]]; then
    progress_arg+=(--no-progress)
  fi

  limit_arg=()
  if [[ "$LIMIT" -gt 0 ]]; then
    limit_arg+=(--limit "$LIMIT")
  fi

  echo
  echo "== DA3 dataset=$ds model=$MODEL_NAME input=$(basename "$input_dir") limit=$LIMIT =="
  "${DOCKER[@]}" run --rm --runtime=nvidia \
    -v "$MODEL_ROOT":/workspace/model \
    -v "$input_dir":/workspace/input:ro \
    -v "$out_dir":/workspace/output \
    -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
    -v "$CACHE_ROOT/huggingface":/workspace/cache/huggingface \
    -v "$CACHE_ROOT/torch":/workspace/cache/torch \
    "$IMAGE" \
    bash -lc "export HF_HOME=/workspace/cache/huggingface TORCH_HOME=/workspace/cache/torch PYTHONPATH=/workspace/model/src:\$PYTHONPATH && python3 /workspace/runner/scripts/jetson/depth_anything3_batch.py --model-root /workspace/model --input-dir /workspace/input --output-dir /workspace/output --model-name \"$MODEL_NAME\" --process-res \"$PROCESS_RES\" ${limit_arg[*]} ${progress_arg[*]}"
done
