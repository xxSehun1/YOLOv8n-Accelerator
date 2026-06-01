"""
Generate Gate C first-CONV vectors.

Outputs:
  Build/input_tiny16_seed0.bin
  Build/golden_l0_tiny16_conv.bin
  Build/full_instructions_gatec_tiny.txt
  Build/npu_program_gatec_tiny.hex
  Build/input_seed0.bin
  Build/golden_l0_conv.bin
  Build/full_instructions_gatec_full.txt
  Build/npu_program_gatec_full.hex

The input and first layer output are produced by the same ISS contract used to
freeze Phase 0: numpy default_rng(seed=0), uint8 CHW layout, zero point 128.
"""
import hashlib
from pathlib import Path

import numpy as np

from assembler import text_to_hex_full
from npu_iss import conv_int8


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def emit_first_conv_case(weights, in_h, in_w, stem):
    in_c = 3
    out_c = 16
    kernel = 3
    stride = 2
    pad = 1
    shift = 0x0A
    flags = 0x00B
    input_bytes = in_h * in_w * in_c
    weight_bytes = out_c * in_c * kernel * kernel + out_c * 4
    out_h = (in_h + 2 * pad - kernel) // stride + 1
    out_w = (in_w + 2 * pad - kernel) // stride + 1

    rng = np.random.default_rng(0)
    img = rng.integers(0, 256, size=input_bytes, dtype=np.uint8)

    blob = np.frombuffer(weights[:weight_bytes], np.uint8)
    w = blob[:out_c * in_c * kernel * kernel].view(np.int8).reshape(
        out_c, in_c, kernel, kernel
    )
    b = blob[out_c * in_c * kernel * kernel:].view(np.int32).copy()
    x = img.reshape(in_c, in_h, in_w).astype(np.int64) - 128
    y = conv_int8(x, w, b, stride, pad, shift, flags)

    if y.shape != (out_c, out_h, out_w):
        raise RuntimeError(f"Unexpected {stem} L0 shape: {y.shape}")

    BUILD.mkdir(parents=True, exist_ok=True)
    if stem == "tiny":
        input_path = BUILD / "input_tiny16_seed0.bin"
        golden_path = BUILD / "golden_l0_tiny16_conv.bin"
    else:
        input_path = BUILD / "input_seed0.bin"
        golden_path = BUILD / "golden_l0_conv.bin"
    instr_path = BUILD / f"full_instructions_gatec_{stem}.txt"
    hex_path = BUILD / f"npu_program_gatec_{stem}.hex"

    input_path.write_bytes(img.tobytes(order="C"))
    golden_path.write_bytes(y.astype(np.uint8, copy=False).tobytes(order="C"))

    instr_path.write_text(
        "\n".join([
            f"OP:DMA_LD | DRAM:0x00000000 | SRAM:0x00000000 | SIZE:0x{input_bytes:08X}",
            "OP:DMA_LD | DRAM:0x01000000 | SRAM:0x00380000 | SIZE:0x000001F0",
            f"OP:CONFIG | IN_H:{in_h} | IN_W:{in_w} | IN_C:3 | OUT_C:16 | STRIDE:2 | PCFG:0x07E | SHIFT:0x0A",
            "OP:CONV   | IN:0x00000000 | WGT:0x00380000 | OUT:0x0012C000 | FLAGS:0xB | STRIDE:2 | PAD:1 | KERNEL:3",
            "OP:HALT   | IN:0x00000000 | WGT:0x00000000 | OUT:0x00000000 | FLAGS:0x0 | STRIDE:0 | PAD:0 | KERNEL:0",
        ]) + "\n"
    )
    text_to_hex_full(str(instr_path), str(hex_path))

    print(f"Wrote {input_path.relative_to(ROOT)} size={input_path.stat().st_size} sha256={sha256(input_path)}")
    print(f"Wrote {golden_path.relative_to(ROOT)} size={golden_path.stat().st_size} sha256={sha256(golden_path)}")
    print(f"Wrote {instr_path.relative_to(ROOT)} size={instr_path.stat().st_size} sha256={sha256(instr_path)}")
    print(f"Wrote {hex_path.relative_to(ROOT)} size={hex_path.stat().st_size} sha256={sha256(hex_path)}")


def main():
    weights = (BUILD / "weights.bin").read_bytes()
    emit_first_conv_case(weights, 16, 16, "tiny")
    emit_first_conv_case(weights, 640, 640, "full")


if __name__ == "__main__":
    main()
