#!/usr/bin/env bash

set -euo pipefail

CONF=${NVP_CONF:-/etc/nvpmodel.conf}

if [[ ! -f "$CONF" ]]; then
  echo "nvpmodel config not found: $CONF" >&2
  exit 1
fi

grep -nE '^[[:space:]]*< POWER_MODEL ID=' "$CONF" | \
  sed -E 's/.*ID=([0-9]+) NAME=([^ >]+).*/\1\t\2/'
