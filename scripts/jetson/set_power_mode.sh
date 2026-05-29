#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  set_power_mode.sh <mode-id|mode-name>
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

TARGET=$1
CONF=${NVP_CONF:-/etc/nvpmodel.conf}

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  MODE_ID=$TARGET
else
  MODE_ID=$(grep -E "< POWER_MODEL ID=[0-9]+ NAME=${TARGET}([ >]|$)" "$CONF" | \
    sed -E 's/.*ID=([0-9]+).*/\1/' | head -n 1)
fi

if [[ -z "${MODE_ID:-}" ]]; then
  echo "Power mode not found: $TARGET" >&2
  exit 1
fi

if sudo -n true >/dev/null 2>&1; then
  sudo -n nvpmodel -m "$MODE_ID"
  sudo -n nvpmodel -q
else
  nvpmodel -m "$MODE_ID"
  nvpmodel -q
fi
