#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Split an enriched initial table report into monocular and stereo subsets.")
    parser.add_argument("--input-json", required=True, help="Path to summary_enriched.json")
    parser.add_argument("--output-dir", required=True, help="Directory where the filtered summaries will be written")
    return parser.parse_args()


def infer_task_family(row: dict) -> str:
    unit = row.get("processed_unit")
    model_key = row.get("model_key")
    if unit == "stereo_pairs" or model_key in {"foundation_stereo", "igev"}:
        return "stereo"
    return "monocular"


def write_csv(path: Path, rows: list[dict]) -> None:
    fieldnames = [
        "model_key",
        "model_name",
        "status",
        "power_mode_id",
        "power_mode_name",
        "profile",
        "task_family",
        "dataset_scope",
        "duration_s",
        "energy_joules",
        "avg_power_w",
        "peak_power_w",
        "primary_power_rail",
        "telemetry_samples",
        "processed_items",
        "processed_unit",
        "throughput_items_s",
        "joules_per_item",
        "flops_g_per_item",
        "jgflops",
        "artifacts_dir",
        "report_dir",
        "notes",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key) for key in fieldnames})


def write_jsonl(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def write_group(output_dir: Path, stem: str, rows: list[dict]) -> None:
    json_path = output_dir / f"{stem}.json"
    csv_path = output_dir / f"{stem}.csv"
    jsonl_path = output_dir / f"{stem}.jsonl"
    json_path.write_text(json.dumps(rows, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_csv(csv_path, rows)
    write_jsonl(jsonl_path, rows)


def main() -> int:
    args = parse_args()
    input_json = Path(args.input_json)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = json.loads(input_json.read_text(encoding="utf-8"))
    for row in rows:
        row.setdefault("task_family", infer_task_family(row))

    monocular_rows = [row for row in rows if row["task_family"] == "monocular"]
    stereo_rows = [row for row in rows if row["task_family"] == "stereo"]

    write_group(output_dir, "summary_monocular_enriched", monocular_rows)
    write_group(output_dir, "summary_stereo_enriched", stereo_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
