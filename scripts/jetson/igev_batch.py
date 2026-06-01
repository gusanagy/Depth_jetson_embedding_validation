#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import imageio.v2 as imageio
import matplotlib.pyplot as plt
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
    parser.add_argument("--left-dir", required=True)
    parser.add_argument("--right-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--ckpt", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--valid-iters", type=int, default=32)
    parser.add_argument("--mixed-precision", action="store_true")
    parser.add_argument("--precision-dtype", default="float16")
    parser.add_argument("--max-disp", type=int, default=192)
    parser.add_argument("--hidden-dims", nargs="+", type=int, default=[128, 128, 128])
    parser.add_argument("--corr-levels", type=int, default=2)
    parser.add_argument("--corr-radius", type=int, default=4)
    parser.add_argument("--n-downsample", type=int, default=2)
    parser.add_argument("--n-gru-layers", type=int, default=3)
    parser.add_argument("--no-progress", action="store_true")
    return parser.parse_args()


def add_model_root(model_root: Path) -> None:
    sys.path.insert(0, str(model_root))
    sys.path.insert(0, str(model_root / "core"))


def list_pairs(left_dir: Path, right_dir: Path, limit: int) -> list[tuple[Path, Path]]:
    pairs = []
    for left_img in sorted(left_dir.iterdir()):
        if not left_img.is_file():
            continue
        right_img = right_dir / left_img.name
        if right_img.is_file():
            pairs.append((left_img, right_img))
    if limit > 0:
        return pairs[:limit]
    return pairs


def load_image(path: Path, device: str) -> torch.Tensor:
    img = np.array(Image.open(path).convert("RGB")).astype(np.uint8)
    tensor = torch.from_numpy(img).permute(2, 0, 1).float()
    return tensor[None].to(device)


def normalize_depth(depth: np.ndarray) -> np.ndarray:
    valid = depth[np.isfinite(depth)]
    if valid.size == 0:
        return np.zeros_like(depth, dtype=np.float32)
    d_min = np.percentile(valid, 2)
    d_max = np.percentile(valid, 98)
    return np.clip((depth - d_min) / (d_max - d_min + 1e-8), 0.0, 1.0)


def patch_timm_for_igev() -> None:
    import timm
    import torch.nn as nn

    if getattr(timm, "_igev_create_model_patched", False):
        return

    original_create_model = timm.create_model

    def patched_create_model(model_name, *args, **kwargs):
        if model_name == "mobilenetv2_100" and kwargs.get("features_only"):
            patched_kwargs = dict(kwargs)
            patched_kwargs.pop("features_only", None)
            patched_kwargs.pop("out_indices", None)
            model = original_create_model(model_name, *args, **patched_kwargs)
            if not hasattr(model, "act1"):
                # Newer timm exposes a plain EfficientNet/MobileNetV2-style model
                # without the top-level activation expected by the original IGEV code.
                model.act1 = nn.ReLU6(inplace=False)
            return model
        return original_create_model(model_name, *args, **kwargs)

    timm.create_model = patched_create_model
    if hasattr(timm, "models") and hasattr(timm.models, "create_model"):
        timm.models.create_model = patched_create_model
    timm._igev_create_model_patched = True


def main() -> int:
    args = parse_args()
    model_root = Path(args.model_root)
    output_dir = Path(args.output_dir)
    raw_disp_dir = output_dir / "raw_disparity"
    raw_depth_dir = output_dir / "raw_depth"
    grayscale_dir = output_dir / "grayscale"
    color_dir = output_dir / "color"
    for path in (raw_disp_dir, raw_depth_dir, grayscale_dir, color_dir):
        path.mkdir(parents=True, exist_ok=True)

    add_model_root(model_root)
    patch_timm_for_igev()
    from igev_stereo import IGEVStereo
    from utils.utils import InputPadder

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = torch.nn.DataParallel(IGEVStereo(args))
    model.load_state_dict(torch.load(args.ckpt, map_location=device))
    model = model.module
    model.to(device)
    model.eval()

    pairs = list_pairs(Path(args.left_dir), Path(args.right_dir), args.limit)
    iterator = pairs if args.no_progress or tqdm is None else tqdm(pairs, desc="IGEV", unit="pair")

    processed = 0
    for left_path, right_path in iterator:
        img_l = load_image(left_path, device)
        img_r = load_image(right_path, device)

        padder = InputPadder(img_l.shape, divis_by=32)
        img_l, img_r = padder.pad(img_l, img_r)

        with torch.no_grad():
            disp = model(img_l, img_r, iters=args.valid_iters, test_mode=True)

        disp = padder.unpad(disp.cpu().numpy()).squeeze()
        depth = 1.0 / np.clip(disp, 1e-8, None)
        norm = normalize_depth(depth)
        grayscale = (norm * 255.0).astype(np.uint8)
        color = (plt.get_cmap("Spectral_r")(norm)[..., :3] * 255).astype(np.uint8)

        stem = left_path.stem
        np.save(raw_disp_dir / f"{stem}.npy", disp)
        np.save(raw_depth_dir / f"{stem}.npy", depth)
        imageio.imwrite(grayscale_dir / f"{stem}.png", grayscale)
        imageio.imwrite(color_dir / f"{stem}.png", color)
        processed += 1

    payload = {
        "checkpoint": args.ckpt,
        "created_at": datetime.now().astimezone().isoformat(),
        "device": device,
        "processed_items": processed,
        "processed_unit": "stereo_pairs",
        "valid_iters": args.valid_iters,
    }
    (output_dir / "batch_run_info.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
