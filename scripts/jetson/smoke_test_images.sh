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

run_one() {
  local name=$1
  local image=$2
  local cmd=$3

  echo
  echo "== Smoke test: $name =="
  docker run --rm --gpus all "$image" bash -lc "$cmd"
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
