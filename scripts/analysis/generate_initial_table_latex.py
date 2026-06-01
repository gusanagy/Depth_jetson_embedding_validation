#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a LaTeX table from an enriched initial table CSV.")
    parser.add_argument("--input-csv", required=True)
    parser.add_argument("--output-tex", required=True)
    parser.add_argument("--caption", default="Preliminary energy and throughput results on the Jetson AGX Thor in 120W mode.")
    parser.add_argument("--label", default="tab:jetson_initial_120w")
    parser.add_argument(
        "--task-filter",
        choices=("all", "monocular", "stereo"),
        default="all",
        help="Restrict the LaTeX table to a single task family if needed.",
    )
    return parser.parse_args()


def fmt_float(value: str | None, digits: int = 2) -> str:
    if value in (None, "", "None"):
        return "N/D"
    return f"{float(value):.{digits}f}"


def infer_task_family(row: dict[str, str]) -> str:
    unit = row.get("processed_unit")
    model_key = row.get("model_key")
    if unit == "stereo_pairs" or model_key in {"foundation_stereo", "igev"}:
        return "stereo"
    return "monocular"


def main() -> int:
    args = parse_args()
    input_csv = Path(args.input_csv)
    output_tex = Path(args.output_tex)

    rows = []
    with input_csv.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row.get("status") == "completed" and (
                args.task_filter == "all" or infer_task_family(row) == args.task_filter
            ):
                rows.append(row)

    task_label = {
        "all": "Mixed",
        "monocular": "Monocular",
        "stereo": "Stereo",
    }[args.task_filter]

    lines = [
        "\\begin{table}[t]",
        "\\centering",
        f"\\caption{{{args.caption}}}",
        f"\\label{{{args.label}}}",
        "\\begin{tabular}{l l r r r r r r r}",
        "\\hline",
        "Model & Family & Items & Time (s) & Throughput & Energy/item & Avg. Power & GFLOPs/item & J/GFLOP \\\\",
        "\\hline",
    ]

    for row in rows:
        unit = row.get("processed_unit") or "items"
        if unit == "images":
            task = "Monocular"
            throughput_unit = "img/s"
            energy_unit = "J/img"
        elif unit == "stereo_pairs":
            task = "Stereo"
            throughput_unit = "pair/s"
            energy_unit = "J/pair"
        else:
            task = "Unknown"
            throughput_unit = "item/s"
            energy_unit = "J/item"

        lines.append(
            f"{row['model_name']} & {task} & {row.get('processed_items', 'N/D')} {unit.replace('_', ' ')} "
            f"& {fmt_float(row.get('duration_s'))} & {fmt_float(row.get('throughput_items_s') or row.get('fps'))} {throughput_unit} "
            f"& {fmt_float(row.get('joules_per_item') or row.get('joules_per_sample'))} {energy_unit} & {fmt_float(row.get('avg_power_w'))} W "
            f"& {fmt_float(row.get('flops_g_per_item') or row.get('flops_g_per_sample'))} & {fmt_float(row.get('jgflops'))} \\\\"
        )

    lines.extend(
        [
            "\\hline",
            "\\end{tabular}",
            "\\vspace{0.4em}",
            "",
            "\\parbox{0.96\\linewidth}{\\footnotesize",
            "\\textbf{Notes:}",
            f"(i) this table corresponds to the {task_label.lower()} subset of the Jetson benchmark;",
            "(ii) throughput was recomputed from the actual number of processed outputs, not from tegrastats samples;",
            "(iii) GFLOPs and J/GFLOP remain as N/D until the per-model FLOPs probes are executed.}",
            "\\end{table}",
            "",
        ]
    )

    output_tex.write_text("\n".join(lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
