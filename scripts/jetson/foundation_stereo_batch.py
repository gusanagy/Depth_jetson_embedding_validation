#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import warnings
from datetime import datetime
from pathlib import Path

import cv2
import imageio.v2 as imageio
import numpy as np
import torch
from matplotlib import pyplot as plt
from omegaconf import OmegaConf

try:
    from tqdm import tqdm
except Exception:  # pragma: no cover - fallback only
    tqdm = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--dataset-root", required=True)
    parser.add_argument("--ckpt", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--hiera", type=int, default=0)
    parser.add_argument("--valid-iters", type=int, default=32)
    parser.add_argument("--progress", action="store_true")
    return parser.parse_args()


def patch_runtime() -> None:
    warnings.filterwarnings(
        "ignore",
        message=r".*torch\.cuda\.amp\.autocast.*deprecated.*",
        category=FutureWarning,
    )
    warnings.filterwarnings(
        "ignore",
        message=r"xFormers is not available.*",
        category=UserWarning,
    )

    logging.getLogger("httpx").setLevel(logging.ERROR)
    logging.getLogger("huggingface_hub").setLevel(logging.ERROR)

    original_torch_load = torch.load

    def patched_torch_load(*load_args, **load_kwargs):
        load_kwargs.setdefault("weights_only", False)
        return original_torch_load(*load_args, **load_kwargs)

    torch.load = patched_torch_load


def add_model_root_to_path(model_root: Path) -> None:
    sys.path.insert(0, str(model_root))


def load_modules(model_root: Path):
    add_model_root_to_path(model_root)
    from Utils import set_logging_format, set_seed
    from core.foundation_stereo import FoundationStereo
    from core.utils.utils import InputPadder

    return set_logging_format, set_seed, FoundationStereo, InputPadder


def load_config(ckpt_path: Path, cli_args: argparse.Namespace) -> OmegaConf:
    cfg_path = ckpt_path.with_name("large_cfg.yaml")
    cfg = OmegaConf.load(cfg_path)
    if "vit_size" not in cfg:
        cfg["vit_size"] = "vitl"

    cfg["scale"] = cli_args.scale
    cfg["hiera"] = cli_args.hiera
    cfg["valid_iters"] = cli_args.valid_iters
    cfg["ckpt_dir"] = str(ckpt_path)
    return OmegaConf.create(cfg)


def list_pairs(dataset_root: Path, limit: int) -> list[tuple[Path, Path]]:
    left_dir = dataset_root / "left"
    right_dir = dataset_root / "right"
    pairs: list[tuple[Path, Path]] = []

    for left_img in sorted(left_dir.iterdir()):
        if not left_img.is_file():
            continue
        right_img = right_dir / left_img.name
        if right_img.is_file():
            pairs.append((left_img, right_img))

    if limit > 0:
        return pairs[:limit]
    return pairs


def prepare_image(path: Path, scale: float) -> np.ndarray:
    img = imageio.imread(path)

    if len(img.shape) == 3 and img.shape[-1] == 4:
        img = img[:, :, :3]

    if len(img.shape) == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2RGB)

    if scale != 1:
        img = cv2.resize(img, fx=scale, fy=scale, dsize=None)

    return img


def infer_depth(
    model,
    InputPadder,
    img0: np.ndarray,
    img1: np.ndarray,
    args: OmegaConf,
    device: str,
) -> np.ndarray:
    h, w = img0.shape[:2]
    img0_tensor = torch.as_tensor(img0).float()[None].permute(0, 3, 1, 2).to(device)
    img1_tensor = torch.as_tensor(img1).float()[None].permute(0, 3, 1, 2).to(device)

    padder = InputPadder(img0_tensor.shape, divis_by=32, force_square=False)
    img0_tensor, img1_tensor = padder.pad(img0_tensor, img1_tensor)

    with torch.amp.autocast("cuda", enabled=device == "cuda"):
        if not args.hiera:
            disp = model.forward(
                img0_tensor,
                img1_tensor,
                iters=args.valid_iters,
                test_mode=True,
            )
        else:
            disp = model.run_hierachical(
                img0_tensor,
                img1_tensor,
                iters=args.valid_iters,
                test_mode=True,
                small_ratio=0.5,
            )

    disp = padder.unpad(disp.float())
    disp = disp.data.cpu().numpy().reshape(h, w)
    disp[disp <= 0] = np.nan

    depth = 1.0 / (disp + 1e-8)
    depth = np.nan_to_num(depth, nan=0.0, posinf=0.0, neginf=0.0)
    return depth


def depth_to_color(depth: np.ndarray) -> np.ndarray:
    valid = depth[depth > 0]
    if len(valid) > 0:
        d_min = np.percentile(valid, 2)
        d_max = np.percentile(valid, 98)
        depth_norm = (depth - d_min) / (d_max - d_min + 1e-8)
        depth_norm = np.clip(depth_norm, 0, 1)
    else:
        depth_norm = np.zeros_like(depth)

    cmap = plt.get_cmap("Spectral")
    depth_color = (cmap(depth_norm)[..., :3] * 255).astype(np.uint8)
    return cv2.cvtColor(depth_color, cv2.COLOR_RGB2BGR)


def save_run_summary(
    out_dir: Path,
    ckpt: Path,
    dataset_root: Path,
    total_pairs: int,
    processed_pairs: int,
    device: str,
) -> None:
    payload = {
        "created_at": datetime.now().astimezone().isoformat(),
        "checkpoint": str(ckpt),
        "dataset_root": str(dataset_root),
        "device": device,
        "processed_pairs": processed_pairs,
        "requested_pairs": total_pairs,
    }
    (out_dir / "batch_run_info.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    cli_args = parse_args()
    patch_runtime()

    model_root = Path(cli_args.model_root)
    dataset_root = Path(cli_args.dataset_root)
    ckpt_path = Path(cli_args.ckpt)
    out_dir = Path(cli_args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    set_logging_format, set_seed, FoundationStereo, InputPadder = load_modules(model_root)
    set_logging_format()
    set_seed(0)
    torch.autograd.set_grad_enabled(False)

    args = load_config(ckpt_path, cli_args)
    device = "cuda" if torch.cuda.is_available() else "cpu"

    logging.info("Usando modelo: %s", ckpt_path)
    logging.info("Device: %s", device)

    model = FoundationStereo(args)
    ckpt = torch.load(str(ckpt_path), map_location=device)
    model.load_state_dict(ckpt["model"])
    model.to(device)
    model.eval()

    pairs = list_pairs(dataset_root, cli_args.limit)
    total_pairs = len(pairs)
    logging.info("FoundationStereo pares para processar: %s", total_pairs)

    use_tqdm = cli_args.progress and tqdm is not None
    iterator = pairs
    if use_tqdm:
        iterator = tqdm(pairs, desc="FoundationStereo", unit="pair")

    processed = 0
    for left_path, right_path in iterator:
        if not use_tqdm:
            logging.info("Processando %s", left_path.name)
        else:
            iterator.set_postfix_str(left_path.name)

        img0 = prepare_image(left_path, args.scale)
        img1 = prepare_image(right_path, args.scale)
        depth = infer_depth(model, InputPadder, img0, img1, args, device)
        depth_color = depth_to_color(depth)

        base_name = left_path.stem
        sample_out_dir = out_dir / base_name
        sample_out_dir.mkdir(parents=True, exist_ok=True)
        out_path = sample_out_dir / f"{base_name}_depth.png"
        cv2.imwrite(str(out_path), depth_color)
        processed += 1

    save_run_summary(out_dir, ckpt_path, dataset_root, total_pairs, processed, device)
    logging.info("FoundationStereo concluido: %s pares processados", processed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
