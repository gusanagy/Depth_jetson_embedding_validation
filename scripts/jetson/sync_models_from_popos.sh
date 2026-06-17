#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sync_models_from_popos.sh [options]

Options:
  --workspace-root PATH   Base workspace root on Jetson.
  --profile NAME          One of: full, code, code_weights. Default: code_weights
  --model NAME            Sync only one model key. Allowed:
                          da2 da3 depthpro marigold foundation igev
  --dry-run               Show rsync operations without copying files.
  -h, --help              Show this help.

Profiles:
  full         Copies almost everything except .git, venv and __pycache__.
  code         Copies source code only, excluding datasets, outputs, checkpoints.
  code_weights Copies source code plus checkpoints/pretrained weights, excluding datasets and outputs.

Source host:
  Set DEPTH_SOURCE_USER and DEPTH_SOURCE_HOST before running.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
PROFILE="code_weights"
ONLY_MODEL=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root)
      WORKSPACE_ROOT=$2
      shift 2
      ;;
    --profile)
      PROFILE=$2
      shift 2
      ;;
    --model)
      ONLY_MODEL=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SOURCE_USER="${DEPTH_SOURCE_USER:-<source-user>}"
SOURCE_HOST="${DEPTH_SOURCE_HOST:-<source-host>}"
TARGET_ROOT="$WORKSPACE_ROOT/external_models"

declare -A SOURCE_PATHS=(
  [da2]="${DEPTH_SOURCE_DA2_PATH:-<source-path-da2>/}"
  [da3]="${DEPTH_SOURCE_DA3_PATH:-<source-path-da3>/}"
  [depthpro]="${DEPTH_SOURCE_DEPTHPRO_PATH:-<source-path-depthpro>/}"
  [marigold]="${DEPTH_SOURCE_MARIGOLD_PATH:-<source-path-marigold>/}"
  [foundation]="${DEPTH_SOURCE_FOUNDATION_PATH:-<source-path-foundation>/}"
  [igev]="${DEPTH_SOURCE_IGEV_PATH:-<source-path-igev>/}"
)

declare -A TARGET_NAMES=(
  [da2]="Depth-Anything-V2"
  [da3]="depth-anything-3"
  [depthpro]="ml-depth-pro"
  [marigold]="Marigold"
  [foundation]="FoundationStereo"
  [igev]="IGEV"
)

common_excludes=(
  --exclude=.git/
  --exclude=venv/
  --exclude=__pycache__/
  --exclude=.mypy_cache/
  --exclude=.pytest_cache/
  --exclude=logs/
  --exclude=output/
  --exclude=outputs/
)

profile_excludes=()
case "$PROFILE" in
  full)
    ;;
  code)
    profile_excludes=(
      --exclude=datasets/
      --exclude=data/
      --exclude=input/
      --exclude=output/
      --exclude=outputs/
      --exclude=logs/
      --exclude=checkpoints/
      --exclude=pretrained_models/
      --exclude=*.pth
      --exclude=*.pt
      --exclude=*.ckpt
      --exclude=*.engine
      --exclude=*.onnx
      --exclude=*.tar
      --exclude=*.tar.gz
    )
    ;;
  code_weights)
    profile_excludes=(
      --exclude=datasets/
      --exclude=data_split/
      --exclude=input/
      --exclude=output/
      --exclude=outputs/
      --exclude=logs/
    )
    ;;
  *)
    echo "Invalid profile: $PROFILE" >&2
    exit 1
    ;;
esac

mkdir -p "$TARGET_ROOT"

if [[ "$SOURCE_USER" == *"<source-user>"* || "$SOURCE_HOST" == *"<source-host>"* ]]; then
  echo "Source host is not configured. Export DEPTH_SOURCE_USER and DEPTH_SOURCE_HOST." >&2
  exit 1
fi

keys=(da2 da3 depthpro marigold foundation igev)
if [[ -n "$ONLY_MODEL" ]]; then
  keys=("$ONLY_MODEL")
fi

extra_flags=()
if [[ $DRY_RUN -eq 1 ]]; then
  extra_flags+=(--dry-run)
fi

for key in "${keys[@]}"; do
  if [[ -z "${SOURCE_PATHS[$key]:-}" ]]; then
    echo "Unknown model key: $key" >&2
    exit 1
  fi

  src="${SOURCE_PATHS[$key]}"
  dst="$TARGET_ROOT/${TARGET_NAMES[$key]}"

  if [[ "$src" == *"<source-path-"* ]]; then
    echo "Source path for '$key' is not configured. Export the matching DEPTH_SOURCE_*_PATH variable." >&2
    exit 1
  fi

  mkdir -p "$dst"

  echo
  echo "== Syncing $key =="
  echo "Source: ${SOURCE_USER}@${SOURCE_HOST}:$src"
  echo "Target: $dst"
  echo "Profile: $PROFILE"

  rsync -avh --progress \
    "${extra_flags[@]}" \
    "${common_excludes[@]}" \
    "${profile_excludes[@]}" \
    -e ssh \
    "${SOURCE_USER}@${SOURCE_HOST}:$src" \
    "$dst/"
done

echo
echo "Model sync finished. Files are under: $TARGET_ROOT"
