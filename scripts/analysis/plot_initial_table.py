#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import matplotlib.pyplot as plt


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Plot initial table summary for Jetson runs.")
    parser.add_argument("--summary-json", required=True, help="Path to summary.json")
    parser.add_argument("--output", required=True, help="Output PNG path")
    parser.add_argument(
        "--enriched-csv",
        help="Optional path to write enriched CSV with derived metrics",
    )
    parser.add_argument(
        "--title",
        default="Initial Table Overview",
        help="Figure title",
    )
    return parser.parse_args()


def load_records(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))


def enrich_records(records: list[dict]) -> list[dict]:
    enriched: list[dict] = []
    for row in records:
        item = dict(row)
        duration = row.get("duration_s")
        processed_items = row.get("processed_items")
        samples = processed_items if processed_items is not None else row.get("samples")
        energy = row.get("energy_joules")

        item["throughput_count"] = samples
        item["throughput_unit"] = row.get("processed_unit") or "items"
        item["telemetry_samples"] = row.get("samples")

        if row.get("throughput_items_s") is not None:
            item["fps"] = row.get("throughput_items_s")
        elif duration and samples:
            item["fps"] = samples / duration
        else:
            item["fps"] = None
        item["throughput_items_s"] = item["fps"]

        if energy and samples:
            item["joules_per_sample"] = energy / samples
        else:
            item["joules_per_sample"] = None
        item["joules_per_item"] = item["joules_per_sample"]

        if energy is not None:
            item["energy_kj"] = energy / 1000.0
        else:
            item["energy_kj"] = None

        item["flops_g_per_sample"] = row.get("flops_g_per_sample")
        item["jgflops"] = None
        if item["flops_g_per_sample"] and item["joules_per_sample"]:
            item["jgflops"] = item["joules_per_sample"] / item["flops_g_per_sample"]

        enriched.append(item)

    return enriched


def fmt(value, digits: int = 2) -> str:
    if value is None:
        return "N/D"
    return f"{value:.{digits}f}"


def write_enriched_csv(path: Path, records: list[dict]) -> None:
    fieldnames = [
        "model_key",
        "model_name",
        "status",
        "power_mode_name",
        "profile",
        "dataset_scope",
        "processed_items",
        "processed_unit",
        "telemetry_samples",
        "samples",
        "duration_s",
        "fps",
        "throughput_items_s",
        "energy_joules",
        "energy_kj",
        "joules_per_sample",
        "joules_per_item",
        "avg_power_w",
        "peak_power_w",
        "flops_g_per_sample",
        "jgflops",
        "notes",
    ]

    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in records:
            writer.writerow({key: row.get(key) for key in fieldnames})


def build_table(ax, records: list[dict]) -> None:
    ax.axis("off")
    headers = [
        "Modelo",
        "Status",
        "Itens proc.",
        "FPS / itens/s",
        "Energia total (kJ)",
        "Energia/item (J)",
        "Pot. media (W)",
        "Pico (W)",
        "FLOPs/img",
    ]

    rows = []
    colors = []
    for row in records:
        rows.append(
            [
                row["model_name"],
                row["status"],
                row.get("throughput_count") or "-",
                fmt(row.get("fps")),
                fmt(row.get("energy_kj")),
                fmt(row.get("joules_per_sample")),
                fmt(row.get("avg_power_w")),
                fmt(row.get("peak_power_w")),
                fmt(row.get("flops_g_per_sample")),
            ]
        )
        if row["status"] == "completed":
            colors.append("#d8f3dc")
        elif row["status"] == "runner_pending":
            colors.append("#fff3bf")
        else:
            colors.append("#f8d7da")

    table = ax.table(
        cellText=rows,
        colLabels=headers,
        cellLoc="center",
        colLoc="center",
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1, 1.6)

    for col in range(len(headers)):
        table[(0, col)].set_facecolor("#264653")
        table[(0, col)].set_text_props(color="white", weight="bold")

    for row_idx, color in enumerate(colors, start=1):
        for col in range(len(headers)):
            table[(row_idx, col)].set_facecolor(color)


def plot_metric_bar(ax, rows: list[dict], key: str, title: str, ylabel: str, color: str) -> None:
    names = [row["model_name"] for row in rows]
    values = [row[key] for row in rows]
    bars = ax.bar(names, values, color=color)
    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.grid(axis="y", linestyle="--", alpha=0.3)
    ax.tick_params(axis="x", rotation=12)

    upper = max(values) * 1.15 if values else 1.0
    ax.set_ylim(0, upper)
    for bar, value in zip(bars, values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height(),
            f"{value:.2f}",
            ha="center",
            va="bottom",
            fontsize=9,
        )


def plot_flops_panel(ax, records: list[dict]) -> None:
    ax.axis("off")
    lines = []
    missing = []
    for row in records:
        if row["status"] != "completed":
            continue
        flops = row.get("flops_g_per_sample")
        if flops is None:
            missing.append(row["model_name"])
        else:
            lines.append(f"{row['model_name']}: {flops:.2f} GFLOPs/img")

    if not lines:
        text = (
            "FLOPs: N/D nesta rodada\n\n"
            "Nenhum arquivo de FLOPs foi encontrado no workspace da Jetson.\n"
            "Modelos concluídos sem FLOPs medidos:\n- "
            + "\n- ".join(missing or ["Nenhum"])
        )
    else:
        text = "FLOPs por imagem\n\n" + "\n".join(lines)

    text += (
        "\n\nObs. de throughput:\n"
        "- DA2: imagens/s usando contagem real de artefatos.\n"
        "- FoundationStereo: pares/s usando batch_run_info.json."
    )

    ax.text(
        0.02,
        0.98,
        text,
        va="top",
        ha="left",
        fontsize=10,
        bbox={"boxstyle": "round,pad=0.5", "facecolor": "#f1faee", "edgecolor": "#457b9d"},
    )


def main() -> int:
    args = parse_args()
    summary_path = Path(args.summary_json)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    records = enrich_records(load_records(summary_path))
    completed = [row for row in records if row["status"] == "completed"]

    fig = plt.figure(figsize=(17, 10))
    gs = fig.add_gridspec(2, 2, height_ratios=[1.2, 1.0])

    ax_table = fig.add_subplot(gs[0, :])
    build_table(ax_table, records)

    ax_fps = fig.add_subplot(gs[1, 0])
    plot_metric_bar(ax_fps, completed, "fps", "Throughput", "itens/s", "#2a9d8f")

    sub = gs[1, 1].subgridspec(2, 1, height_ratios=[1.0, 1.0])
    ax_energy = fig.add_subplot(sub[0, 0])
    plot_metric_bar(
        ax_energy,
        completed,
        "joules_per_sample",
        "Energia Por Item",
        "J/item",
        "#e76f51",
    )
    ax_flops = fig.add_subplot(sub[1, 0])
    plot_flops_panel(ax_flops, records)

    fig.suptitle(args.title, fontsize=16, weight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    fig.savefig(output_path, dpi=180)

    if args.enriched_csv:
        write_enriched_csv(Path(args.enriched_csv), records)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
