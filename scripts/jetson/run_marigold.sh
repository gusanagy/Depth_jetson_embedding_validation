#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_marigold.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset NAME          Dataset name under the chosen dataset root. Default: all
  --dataset-root PATH     Override dataset root. Default: model datasets fallback to DA2 datasets
  --checkpoint NAME       Default: prs-eth/marigold-depth-v1-1
  --denoise-steps N       Default: 4
  --ensemble-size N       Default: 1
  --processing-res N      Default: 384
  --limit N               Optional image limit.
  --fp16                  Enable half precision on CUDA.
  --image IMAGE           Docker image tag. Default: depth-jetson-marigold:thor-jp71
  --no-progress           Disable tqdm progress bar.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="all"
DATASET_ROOT=""
CHECKPOINT="prs-eth/marigold-depth-v1-1"
DENOISE_STEPS=4
ENSEMBLE_SIZE=1
PROCESSING_RES=384
LIMIT=0
FP16=0
IMAGE="depth-jetson-marigold:thor-jp71"
SHOW_PROGRESS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --checkpoint) CHECKPOINT=$2; shift 2 ;;
    --denoise-steps) DENOISE_STEPS=$2; shift 2 ;;
    --ensemble-size) ENSEMBLE_SIZE=$2; shift 2 ;;
    --processing-res) PROCESSING_RES=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
    --fp16) FP16=1; shift ;;
    --image) IMAGE=$2; shift 2 ;;
    --no-progress) SHOW_PROGRESS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

MODEL_ROOT="$WORKSPACE_ROOT/external_models/Marigold"
OUTPUT_ROOT="$WORKSPACE_ROOT/artifacts/marigold"
CACHE_ROOT="$WORKSPACE_ROOT/cache/marigold"

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
  echo "Build it with: bash scripts/jetson/build_docker_images.sh --only marigold" >&2
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

  out_dir="$OUTPUT_ROOT/$ds"
  mkdir -p "$out_dir"

  progress_arg=()
  if [[ $SHOW_PROGRESS -eq 0 ]]; then
    progress_arg+=(--no-progress)
  fi

  limit_arg=()
  if [[ "$LIMIT" -gt 0 ]]; then
    limit_arg+=(--limit "$LIMIT")
  fi

  fp16_arg=()
  if [[ $FP16 -eq 1 ]]; then
    fp16_arg+=(--fp16)
  fi

  echo
  echo "== Marigold dataset=$ds input=$(basename "$input_dir") limit=$LIMIT =="
  "${DOCKER[@]}" run --rm --runtime=nvidia \
    --ipc=host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -v "$MODEL_ROOT":/workspace/model \
    -v "$input_dir":/workspace/input:ro \
    -v "$out_dir":/workspace/output \
    -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
    -v "$CACHE_ROOT/huggingface":/workspace/cache/huggingface \
    -v "$CACHE_ROOT/torch":/workspace/cache/torch \
    "$IMAGE" \
    bash -lc "export HF_HOME=/workspace/cache/huggingface TORCH_HOME=/workspace/cache/torch PYTHONPATH=/workspace/model:\$PYTHONPATH && python3 /workspace/runner/scripts/jetson/marigold_batch.py --model-root /workspace/model --input-dir /workspace/input --output-dir /workspace/output --checkpoint \"$CHECKPOINT\" --denoise-steps \"$DENOISE_STEPS\" --ensemble-size \"$ENSEMBLE_SIZE\" --processing-res \"$PROCESSING_RES\" ${limit_arg[*]} ${fp16_arg[*]} ${progress_arg[*]}"
done
