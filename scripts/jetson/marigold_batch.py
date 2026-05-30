#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import imageio.v2 as imageio
import numpy as np
import torch
from PIL import Image

try:
    from tqdm import tqdm
except Exception:  # pragma: no cover
    tqdm = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--checkpoint", default="prs-eth/marigold-depth-v1-1")
    parser.add_argument("--denoise-steps", type=int, default=4)
    parser.add_argument("--ensemble-size", type=int, default=1)
    parser.add_argument("--processing-res", type=int, default=384)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--fp16", action="store_true")
    parser.add_argument("--no-progress", action="store_true")
    return parser.parse_args()


def add_model_root(model_root: Path) -> None:
    sys.path.insert(0, str(model_root))


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
    from marigold import MarigoldDepthPipeline

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    dtype = torch.float16 if args.fp16 and device.type == "cuda" else torch.float32
    variant = "fp16" if dtype == torch.float16 else None
    pipe = MarigoldDepthPipeline.from_pretrained(args.checkpoint, variant=variant, torch_dtype=dtype)
    try:
        pipe.enable_xformers_memory_efficient_attention()
    except Exception:
        pass
    pipe = pipe.to(device)

    image_paths = list_images(input_dir, args.limit)
    iterator = image_paths if args.no_progress or tqdm is None else tqdm(image_paths, desc="Marigold", unit="img")

    processed = 0
    for image_path in iterator:
        image = Image.open(image_path).convert("RGB")
        output = pipe(
            image,
            denoising_steps=args.denoise_steps,
            ensemble_size=args.ensemble_size,
            processing_res=args.processing_res,
            color_map="Spectral",
            show_progress_bar=not args.no_progress,
        )
        depth = np.asarray(output.depth_np, dtype=np.float32)
        grayscale = np.clip(depth, 0.0, 1.0)
        grayscale = (grayscale * 255.0).astype(np.uint8)

        np.save(raw_dir / f"{image_path.stem}.npy", depth)
        imageio.imwrite(grayscale_dir / f"{image_path.stem}.png", grayscale)
        if output.depth_colored is not None:
            output.depth_colored.save(color_dir / f"{image_path.stem}.png")
        processed += 1

    payload = {
        "checkpoint": args.checkpoint,
        "created_at": datetime.now().astimezone().isoformat(),
        "device": str(device),
        "denoise_steps": args.denoise_steps,
        "ensemble_size": args.ensemble_size,
        "processed_items": processed,
        "processed_unit": "images",
        "processing_res": args.processing_res,
    }
    (output_dir / "batch_run_info.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
