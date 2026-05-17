"""
YOLOv8n NPU compiler entry point.

Usage
-----
    python main.py
    python main.py --model path/to/model.onnx --outdir ../Build --input-shape 1,3,640,640
"""

import argparse
import sys
from pathlib import Path

import onnx
import tvm
import tvm.relay as relay

from emitter   import NPUFullProgramEmitter
from assembler import text_to_hex_full
from memory    import (ISA_MAX_INSTRUCTIONS,
                       SRAM_ACT_SIZE, DRAM_WEIGHT_SIZE)


def parse_args():
    p = argparse.ArgumentParser(description="YOLOv8n NPU compiler")
    p.add_argument("--model", default="../Model/train/weights/best_int8.onnx",
                   help="Path to INT8 ONNX model (default: %(default)s)")
    p.add_argument("--outdir", default="../Build",
                   help="Output directory (default: %(default)s)")
    p.add_argument("--input-shape", default="1,3,640,640", metavar="N,C,H,W",
                   help="Model input shape (default: %(default)s)")
    return p.parse_args()


def main():
    args = parse_args()
    out  = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    try:
        n, c, h, w = (int(x) for x in args.input_shape.split(','))
    except ValueError:
        sys.exit(f"error: --input-shape must be N,C,H,W  got '{args.input_shape}'")

    # 1. Load ONNX model.
    print(f"Loading model : {args.model}")
    onnx_model  = onnx.load(args.model)
    mod, params = relay.frontend.from_onnx(onnx_model, {"images": (n, c, h, w)})

    # 2. TVM optimisation passes.
    print("Running optimisation passes and INT8 quantisation...")
    with tvm.transform.PassContext(opt_level=1):
        mod["main"] = relay.build_module.bind_params_by_name(mod["main"], params)
        mod = relay.transform.InferType()(mod)
        mod = relay.transform.FakeQuantizationToInteger()(mod)
        mod = relay.transform.FoldConstant()(mod)

        # 3. Instruction emission.
        emitter = NPUFullProgramEmitter(params)
        emitter.visit(mod["main"])

    emitter.instructions.append(
        "OP:HALT   | IN:0x00000000 | WGT:0x00000000 | "
        "OUT:0x00000000 | FLAGS:0x0 | STRIDE:0 | PAD:0 | KERNEL:0"
    )

    # 4. Write instruction text.
    instr_file = out / "full_instructions.txt"
    with open(instr_file, "w") as f:
        f.write("\n".join(emitter.instructions) + "\n")
    n_instr = len(emitter.instructions)
    print(f"  Instructions : {instr_file}  ({n_instr} lines)")

    # 5. Assemble to hex.
    hex_file = out / "npu_program.hex"
    text_to_hex_full(str(instr_file), str(hex_file))
    print(f"  Hex program  : {hex_file}")

    # 6. Export quantised weights.
    weight_file = out / "weights.bin"
    weights     = emitter.weight_memory[:emitter.weight_alloc.used]
    with open(weight_file, "wb") as f:
        f.write(weights)
    print(f"  Weights      : {weight_file}  ({len(weights) / 1024 / 1024:.2f} MB)")

    # 7. Generate CPU fallback runtime.
    runtime_file = out / "cpu_runtime.py"
    _write_cpu_runtime(runtime_file, emitter)
    print(f"  CPU runtime  : {runtime_file}")

    # 7b. Per-layer Eyeriss mapping / PE-array config.
    mapping_file = out / "mapping.txt"
    _write_mapping(mapping_file, emitter)
    print(f"  Mapping      : {mapping_file}  ({len(emitter.mappings)} conv layers)")

    # 8. Resource report.
    _report(emitter, n_instr)
    print("Compilation complete.")


def _write_cpu_runtime(path, emitter):
    """Generate Python stubs for every CPU-fallback op (operates on DRAM)."""
    lines = ["import numpy as np\n\n"]
    for op in sorted(emitter.cpu_op_names):
        fn = op.replace('.', '_')
        lines.append(f"def cpu_execute_{fn}(dram, in_addr, out_addr, h, w, c):\n"
                     f"    pass\n\n")

    lines.append("def handle_npu_interrupt(dram, interrupt_pc):\n")
    if not emitter.cpu_tasks:
        lines.append("    pass\n")
    else:
        lines.append("    if interrupt_pc < 0:\n        pass\n")
        lines.extend(emitter.cpu_tasks)

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def _write_mapping(path, emitter):
    """Write the Eyeriss mapping.

    The GIN/GON scan chains, LN_CONFIG and PE_EN are purely geometric and
    therefore identical for every layer — they are emitted once in a
    [SHARED] section (the hardware scans them in once at startup). Each
    conv layer then needs only its mapping params and PE_CONFIG.
    """
    def csv(xs):
        return ",".join(str(v) for v in xs)

    lines = []
    if emitter.mappings:
        s = emitter.mappings[0][1]                 # chains are layer-independent
        lines.append("[SHARED]   # scanned into GIN/GON once at startup")
        lines.append(f"LN_CONFIG : 0x{s.ln_config:X}")
        lines.append(f"PE_EN     : 0x{s.pe_en:X}")
        lines.append(f"filter_XID: {csv(s.filter_xid)}")
        lines.append(f"filter_YID: {csv(s.filter_yid)}")
        lines.append(f"ifmap_XID : {csv(s.ifmap_xid)}")
        lines.append(f"ifmap_YID : {csv(s.ifmap_yid)}")
        lines.append(f"ipsum_XID : {csv(s.ipsum_xid)}")
        lines.append(f"ipsum_YID : {csv(s.ipsum_yid)}")
        lines.append(f"opsum_XID : {csv(s.opsum_xid)}")
        lines.append(f"opsum_YID : {csv(s.opsum_yid)}")
        lines.append("")

    lines.append("[LAYERS]   # per-conv: mapping params + PE_CONFIG")
    for i, (_, lm) in enumerate(emitter.mappings):
        tag = "" if lm.valid else "   (fallback)"
        lines.append(f"conv {i:2d}: m={lm.m} n={lm.n} e={lm.e} p={lm.p} "
                     f"q={lm.q} r={lm.r} t={lm.t}  "
                     f"PE_CONFIG=0x{lm.pe_config:03X}  "
                     f"strip={lm.ofmap_strip} n_strips={lm.n_strips}  "
                     f"cost={lm.cost} util={lm.util:.2f}{tag}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def _report(emitter, n_instr):
    """Print resource usage and warn on region overflows."""
    act    = emitter.fmap_alloc.used        # SRAM activation peak (high-water)
    weight = emitter.weight_alloc.used      # DRAM weight bytes
    print(f"  SRAM act peak: {act / 1024 / 1024:.2f} / "
          f"{SRAM_ACT_SIZE / 1024 / 1024:.2f} MiB")
    print(f"  DRAM weight  : {weight / 1024 / 1024:.2f} / "
          f"{DRAM_WEIGHT_SIZE / 1024 / 1024:.0f} MiB")

    if act > SRAM_ACT_SIZE:
        print(f"  WARNING: activation SRAM overflows by "
              f"{(act - SRAM_ACT_SIZE) / 1024 / 1024:.2f} MiB")
    if n_instr > ISA_MAX_INSTRUCTIONS:
        print(f"  WARNING: program ({n_instr} instr) exceeds ISA region "
              f"({ISA_MAX_INSTRUCTIONS} instr)")


if __name__ == "__main__":
    main()
