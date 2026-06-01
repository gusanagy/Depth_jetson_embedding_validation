#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  finalize_initial_table_report.sh [options]

Options:
  --workspace-root PATH  Default: ~/Documents/depth_validation_workspace
  --label NAME           Report label. Required.
  --title TEXT           Optional PNG title override.
  --caption TEXT         Optional LaTeX caption override.
  --latex-label TEXT     Optional LaTeX label override.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
LABEL=""
TITLE=""
CAPTION=""
LATEX_LABEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --title) TITLE=$2; shift 2 ;;
    --caption) CAPTION=$2; shift 2 ;;
    --latex-label) LATEX_LABEL=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$LABEL" ]]; then
  echo "--label is required" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REPORT_ROOT="$WORKSPACE_ROOT/reports/initial_table/$LABEL"
MANIFEST_JSON="$REPORT_ROOT/report_manifest.json"

if [[ ! -d "$REPORT_ROOT" ]]; then
  echo "Report root not found: $REPORT_ROOT" >&2
  exit 1
fi

TITLE=${TITLE:-"Initial Table - $LABEL"}
CAPTION=${CAPTION:-"Preliminary energy and throughput results on the Jetson AGX Thor for report $LABEL."}
LATEX_LABEL=${LATEX_LABEL:-"tab:${LABEL//-/_}"}
MONO_TITLE="${TITLE} - Monocular"
STEREO_TITLE="${TITLE} - Stereo"
MONO_CAPTION="Monocular subset of the Jetson AGX Thor benchmark for report $LABEL."
STEREO_CAPTION="Stereo subset of the Jetson AGX Thor benchmark for report $LABEL."
MONO_LATEX_LABEL="${LATEX_LABEL}:monocular"
STEREO_LATEX_LABEL="${LATEX_LABEL}:stereo"

python3 "$REPO_ROOT/scripts/jetson/backfill_initial_table_report.py" \
  --report-root "$REPORT_ROOT" \
  --write-enriched-summary

MPLCONFIGDIR=/tmp/mpl python3 "$REPO_ROOT/scripts/analysis/plot_initial_table.py" \
  --summary-json "$REPORT_ROOT/summary_enriched.json" \
  --output "$REPORT_ROOT/${LABEL}_plot.png" \
  --enriched-csv "$REPORT_ROOT/summary_enriched.csv" \
  --title "$TITLE"

python3 "$REPO_ROOT/scripts/analysis/generate_initial_table_latex.py" \
  --input-csv "$REPORT_ROOT/summary_enriched.csv" \
  --output-tex "$REPORT_ROOT/table_publication.tex" \
  --caption "$CAPTION" \
  --label "$LATEX_LABEL"

python3 "$REPO_ROOT/scripts/analysis/split_initial_table_summary.py" \
  --input-json "$REPORT_ROOT/summary_enriched.json" \
  --output-dir "$REPORT_ROOT"

MPLCONFIGDIR=/tmp/mpl python3 "$REPO_ROOT/scripts/analysis/plot_initial_table.py" \
  --summary-json "$REPORT_ROOT/summary_monocular_enriched.json" \
  --output "$REPORT_ROOT/${LABEL}_monocular_plot.png" \
  --enriched-csv "$REPORT_ROOT/summary_monocular_enriched.csv" \
  --title "$MONO_TITLE"

MPLCONFIGDIR=/tmp/mpl python3 "$REPO_ROOT/scripts/analysis/plot_initial_table.py" \
  --summary-json "$REPORT_ROOT/summary_stereo_enriched.json" \
  --output "$REPORT_ROOT/${LABEL}_stereo_plot.png" \
  --enriched-csv "$REPORT_ROOT/summary_stereo_enriched.csv" \
  --title "$STEREO_TITLE"

python3 "$REPO_ROOT/scripts/analysis/generate_initial_table_latex.py" \
  --input-csv "$REPORT_ROOT/summary_monocular_enriched.csv" \
  --output-tex "$REPORT_ROOT/table_publication_monocular.tex" \
  --caption "$MONO_CAPTION" \
  --label "$MONO_LATEX_LABEL" \
  --task-filter monocular

python3 "$REPO_ROOT/scripts/analysis/generate_initial_table_latex.py" \
  --input-csv "$REPORT_ROOT/summary_stereo_enriched.csv" \
  --output-tex "$REPORT_ROOT/table_publication_stereo.tex" \
  --caption "$STEREO_CAPTION" \
  --label "$STEREO_LATEX_LABEL" \
  --task-filter stereo

python3 - "$MANIFEST_JSON" "$LABEL" "$REPORT_ROOT" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
label = sys.argv[2]
report_root = Path(sys.argv[3]).resolve()
payload = {
    "label": label,
    "report_root": str(report_root),
    "summary_csv": str((report_root / "summary.csv").resolve()),
    "summary_json": str((report_root / "summary.json").resolve()),
    "summary_enriched_csv": str((report_root / "summary_enriched.csv").resolve()),
    "summary_enriched_json": str((report_root / "summary_enriched.json").resolve()),
    "summary_enriched_jsonl": str((report_root / "summary_enriched.jsonl").resolve()),
    "summary_monocular_enriched_csv": str((report_root / "summary_monocular_enriched.csv").resolve()),
    "summary_monocular_enriched_json": str((report_root / "summary_monocular_enriched.json").resolve()),
    "summary_monocular_enriched_jsonl": str((report_root / "summary_monocular_enriched.jsonl").resolve()),
    "summary_stereo_enriched_csv": str((report_root / "summary_stereo_enriched.csv").resolve()),
    "summary_stereo_enriched_json": str((report_root / "summary_stereo_enriched.json").resolve()),
    "summary_stereo_enriched_jsonl": str((report_root / "summary_stereo_enriched.jsonl").resolve()),
    "plot_png": str((report_root / f"{label}_plot.png").resolve()),
    "plot_monocular_png": str((report_root / f"{label}_monocular_plot.png").resolve()),
    "plot_stereo_png": str((report_root / f"{label}_stereo_plot.png").resolve()),
    "latex_tex": str((report_root / "table_publication.tex").resolve()),
    "latex_monocular_tex": str((report_root / "table_publication_monocular.tex").resolve()),
    "latex_stereo_tex": str((report_root / "table_publication_stereo.tex").resolve()),
}
manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Report root: $REPORT_ROOT"
echo "CSV: $REPORT_ROOT/summary_enriched.csv"
echo "PNG: $REPORT_ROOT/${LABEL}_plot.png"
echo "LaTeX: $REPORT_ROOT/table_publication.tex"
echo "Monocular CSV: $REPORT_ROOT/summary_monocular_enriched.csv"
echo "Monocular PNG: $REPORT_ROOT/${LABEL}_monocular_plot.png"
echo "Monocular LaTeX: $REPORT_ROOT/table_publication_monocular.tex"
echo "Stereo CSV: $REPORT_ROOT/summary_stereo_enriched.csv"
echo "Stereo PNG: $REPORT_ROOT/${LABEL}_stereo_plot.png"
echo "Stereo LaTeX: $REPORT_ROOT/table_publication_stereo.tex"
echo "Manifest: $MANIFEST_JSON"
