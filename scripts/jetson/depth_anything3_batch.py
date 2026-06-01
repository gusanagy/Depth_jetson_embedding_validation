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

try:
    from tqdm import tqdm
except Exception:  # pragma: no cover
    tqdm = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--model-name", default="da3-large")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--process-res", type=int, default=504)
    parser.add_argument("--no-progress", action="store_true")
    return parser.parse_args()


def add_model_root(model_root: Path) -> None:
    src_dir = model_root / "src"
    sys.path.insert(0, str(src_dir))


def build_shim(name: str):
    class _Shim:
        def __getattr__(self, attr):
            raise RuntimeError(f"{name} shim loaded: optional dependency unavailable for this runner")

    return _Shim()


def install_optional_shims() -> None:
    import types

    if "open3d" not in sys.modules:
        mod = types.ModuleType("open3d")
        mod.geometry = build_shim("open3d")
        mod.utility = build_shim("open3d")
        mod.io = build_shim("open3d")
        sys.modules["open3d"] = mod

    if "pycolmap" not in sys.modules:
        sys.modules["pycolmap"] = build_shim("pycolmap")

    if "plyfile" not in sys.modules:
        mod = types.ModuleType("plyfile")

        class _Unavailable:
            def __init__(self, *args, **kwargs):
                raise RuntimeError("plyfile shim loaded: optional dependency unavailable for this runner")

        mod.PlyData = _Unavailable
        mod.PlyElement = _Unavailable
        sys.modules["plyfile"] = mod

    if "moviepy" not in sys.modules:
        import types

        moviepy = types.ModuleType("moviepy")
        editor = types.ModuleType("moviepy.editor")
        editor.ImageSequenceClip = build_shim("moviepy.editor")
        moviepy.editor = editor
        sys.modules["moviepy"] = moviepy
        sys.modules["moviepy.editor"] = editor

    if "trimesh" not in sys.modules:
        sys.modules["trimesh"] = build_shim("trimesh")

    if "gsplat" not in sys.modules:
        sys.modules["gsplat"] = build_shim("gsplat")


def install_export_shim() -> None:
    import types

    module_name = "depth_anything_3.utils.export"
    if module_name in sys.modules:
        return

    export_module = types.ModuleType(module_name)

    def _noop_export(*args, **kwargs):
        return None

    export_module.export = _noop_export
    export_module.export_to_colmap = _noop_export
    export_module.export_to_glb = _noop_export
    export_module.export_to_gs_ply = _noop_export
    export_module.export_to_gs_video = _noop_export
    export_module.__all__ = [
        "export",
        "export_to_colmap",
        "export_to_glb",
        "export_to_gs_ply",
        "export_to_gs_video",
    ]
    sys.modules[module_name] = export_module


def install_evo_shim() -> None:
    import types

    if "evo.core.trajectory" in sys.modules:
        return

    evo_module = types.ModuleType("evo")
    core_module = types.ModuleType("evo.core")
    trajectory_module = types.ModuleType("evo.core.trajectory")

    class PosePath3D:  # pragma: no cover - import compatibility shim
        def __init__(self, *args, **kwargs):
            self.args = args
            self.kwargs = kwargs

    trajectory_module.PosePath3D = PosePath3D
    core_module.trajectory = trajectory_module
    evo_module.core = core_module

    sys.modules["evo"] = evo_module
    sys.modules["evo.core"] = core_module
    sys.modules["evo.core.trajectory"] = trajectory_module


def list_images(input_dir: Path, limit: int) -> list[Path]:
    files = [
        path
        for path in sorted(input_dir.iterdir())
        if path.is_file() and path.suffix.lower() in {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"}
    ]
    if limit > 0:
        return files[:limit]
    return files


def normalize_depth(depth: np.ndarray) -> np.ndarray:
    valid = depth[np.isfinite(depth)]
    if valid.size == 0:
        return np.zeros_like(depth, dtype=np.float32)
    d_min = np.percentile(valid, 2)
    d_max = np.percentile(valid, 98)
    norm = (depth - d_min) / (d_max - d_min + 1e-8)
    return np.clip(norm, 0.0, 1.0)


def main() -> int:
    args = parse_args()
    model_root = Path(args.model_root)
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    raw_dir = output_dir / "raw"
    grayscale_dir = output_dir / "grayscale"
    color_dir = output_dir / "color"
    raw_dir.mkdir(exist_ok=True)
    grayscale_dir.mkdir(exist_ok=True)
    color_dir.mkdir(exist_ok=True)

    install_optional_shims()
    install_export_shim()
    install_evo_shim()
    add_model_root(model_root)

    from depth_anything_3.api import DepthAnything3

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = DepthAnything3.from_pretrained(args.model_name).to(device)

    image_paths = list_images(input_dir, args.limit)
    iterator = image_paths if args.no_progress or tqdm is None else tqdm(image_paths, desc="DA3", unit="img")

    processed = 0
    for image_path in iterator:
        prediction = model.inference(
            image=[str(image_path)],
            export_dir=None,
            process_res=args.process_res,
            export_format="mini_npz",
        )
        depth = prediction.depth[0]
        depth_norm = normalize_depth(depth)
        grayscale = (depth_norm * 255.0).astype(np.uint8)
        color = cv2.applyColorMap(grayscale, cv2.COLORMAP_INFERNO)

        np.save(raw_dir / f"{image_path.stem}.npy", depth)
        imageio.imwrite(grayscale_dir / f"{image_path.stem}.png", grayscale)
        imageio.imwrite(color_dir / f"{image_path.stem}.png", color)
        processed += 1

    payload = {
        "created_at": datetime.now().astimezone().isoformat(),
        "device": device,
        "input_dir": str(input_dir),
        "model_name": args.model_name,
        "processed_items": processed,
        "processed_unit": "images",
        "process_res": args.process_res,
    }
    (output_dir / "batch_run_info.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
