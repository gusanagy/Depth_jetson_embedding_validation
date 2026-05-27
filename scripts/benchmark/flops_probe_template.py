#!/usr/bin/env python3

"""
Template minimo para medir FLOPs/MACs/params em modelos PyTorch.

Uso esperado:

1. Copiar este script para dentro do repo do modelo.
2. Implementar `build_model()` e `make_inputs()`.
3. Rodar dentro do ambiente do modelo na Jetson ou no host de referencia.

Exemplo:
  python flops_probe_template.py --height 518 --width 518 --channels 3
"""

from __future__ import annotations

import argparse
import json

import torch


def build_model() -> torch.nn.Module:
    raise NotImplementedError("Implemente build_model() para o repo alvo.")


def make_inputs(height: int, width: int, channels: int) -> tuple[torch.Tensor, ...]:
    tensor = torch.randn(1, channels, height, width)
    return (tensor,)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--channels", type=int, default=3)
    args = parser.parse_args()

    model = build_model().eval()
    inputs = make_inputs(args.height, args.width, args.channels)

    result: dict[str, object] = {
        "input_shape": [list(t.shape) for t in inputs],
        "backend": None,
        "flops": None,
        "macs": None,
        "params": sum(p.numel() for p in model.parameters()),
    }

    try:
        from calflops import calculate_flops

        flops, macs, params = calculate_flops(
            model=model,
            args=inputs,
            print_results=False,
            print_detailed=False,
        )
        result.update(
            {
                "backend": "calflops",
                "flops": flops,
                "macs": macs,
                "params": params,
            }
        )
    except Exception:
        try:
            from ptflops import get_model_complexity_info

            with torch.no_grad():
                macs, params = get_model_complexity_info(
                    model,
                    tuple(inputs[0].shape[1:]),
                    as_strings=False,
                    print_per_layer_stat=False,
                    verbose=False,
                )
            result.update(
                {
                    "backend": "ptflops",
                    "flops": macs * 2,
                    "macs": macs,
                    "params": params,
                }
            )
        except Exception as exc:
            result["error"] = (
                "Nao foi possivel calcular FLOPs com calflops nem ptflops: "
                f"{exc}"
            )

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
