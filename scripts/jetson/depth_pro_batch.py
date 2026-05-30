#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import cv2
import imageio.v2 as imageio
import numpy as np
import torch
from matplotlib import pyplot as plt

try:
    from tqdm import tqdm
except Exception:  # pragma: no cover
    tqdm = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--no-progress", action="store_true")
    return parser.parse_args()


def add_model_root(model_root: Path) -> None:
    sys.path.insert(0, str(model_root / "src"))


def list_images(input_dir: Path, limit: int) -> list[Path]:
    files = [
        path
        for path in sorted(input_dir.iterdir())
        if path.is_file() and path.suffix.lower() in {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"}
    ]
    if limit > 0:
        return files[:limit]
    return files


def main() -> int:
    args = parse_args()
    model_root = Path(args.model_root)
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    raw_dir = output_dir / "raw"
    grayscale_dir = output_dir / "grayscale"
    color_dir = output_dir / "color"
    raw_dir.mkdir(parents=True, exist_ok=True)
    grayscale_dir.mkdir(exist_ok=True)
    color_dir.mkdir(exist_ok=True)

    add_model_root(model_root)
    from depth_pro import create_model_and_transforms, load_rgb

    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
    model, transform = create_model_and_transforms(device=device, precision=torch.half if device.type == "cuda" else torch.float32)
    model.eval()
    cmap = plt.get_cmap("Spectral_r")

    image_paths = list_images(input_dir, args.limit)
    iterator = image_paths if args.no_progress or tqdm is None else tqdm(image_paths, desc="DepthPro", unit="img")

    processed = 0
    for image_path in iterator:
        image, _, f_px = load_rgb(image_path)
        prediction = model.infer(transform(image), f_px=f_px)
        depth = prediction["depth"].detach().cpu().numpy().squeeze()
        inverse_depth = 1.0 / np.clip(depth, 1e-8, None)
        d_min = np.percentile(inverse_depth, 2)
        d_max = np.percentile(inverse_depth, 98)
        inv_norm = np.clip((inverse_depth - d_min) / (d_max - d_min + 1e-8), 0.0, 1.0)

        grayscale = (inv_norm * 255.0).astype(np.uint8)
        color = (cmap(inv_norm)[..., :3] * 255).astype(np.uint8)
        color = cv2.cvtColor(color, cv2.COLOR_RGB2BGR)

        np.save(raw_dir / f"{image_path.stem}.npy", depth)
        imageio.imwrite(grayscale_dir / f"{image_path.stem}.png", grayscale)
        imageio.imwrite(color_dir / f"{image_path.stem}.png", color)
        processed += 1

    payload = {
        "created_at": datetime.now().astimezone().isoformat(),
        "device": str(device),
        "input_dir": str(input_dir),
        "processed_items": processed,
        "processed_unit": "images",
    }
    (output_dir / "batch_run_info.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
