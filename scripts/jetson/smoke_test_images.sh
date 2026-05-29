#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  smoke_test_images.sh [--only base|mono|stereo]

Runs lightweight import checks inside the Docker images built for the Jetson.
EOF
}

ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      ONLY=$2
      shift 2
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

if docker info >/dev/null 2>&1; then
  DOCKER_CMD=(docker)
elif sudo -n docker info >/dev/null 2>&1; then
  DOCKER_CMD=(sudo -n docker)
else
  echo "Docker is installed but not accessible for the current user." >&2
  echo "Either add the user to the docker group or allow passwordless sudo for docker." >&2
  exit 1
fi

if "${DOCKER_CMD[@]}" info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
  GPU_ARGS=(--runtime=nvidia)
else
  GPU_ARGS=(--gpus all)
fi

run_one() {
  local name=$1
  local image=$2
  local cmd=$3

  echo
  echo "== Smoke test: $name =="
  "${DOCKER_CMD[@]}" run --rm "${GPU_ARGS[@]}" "$image" bash -lc "$cmd"
}

case "$ONLY" in
  "")
    run_one base depth-jetson-base:thor-jp71 "python3 -c \"import torch; print({'torch': torch.__version__, 'cuda': torch.cuda.is_available()})\""
    run_one mono depth-jetson-mono:thor-jp71 "python3 -c \"import cv2, numpy, pandas, torch; print({'cv2': cv2.__version__, 'torch': torch.__version__})\""
    run_one stereo depth-jetson-stereo:thor-jp71 "python3 -c \"import cv2, timm, torch; print({'timm': timm.__version__, 'torch': torch.__version__})\""
    ;;
  base)
    run_one base depth-jetson-base:thor-jp71 "python3 -c \"import torch; print({'torch': torch.__version__, 'cuda': torch.cuda.is_available()})\""
    ;;
  mono)
    run_one mono depth-jetson-mono:thor-jp71 "python3 -c \"import cv2, numpy, pandas, torch; print({'cv2': cv2.__version__, 'torch': torch.__version__})\""
    ;;
  stereo)
    run_one stereo depth-jetson-stereo:thor-jp71 "python3 -c \"import cv2, timm, torch; print({'timm': timm.__version__, 'torch': torch.__version__})\""
    ;;
  *)
    echo "Invalid --only value: $ONLY" >&2
    exit 1
    ;;
esac
