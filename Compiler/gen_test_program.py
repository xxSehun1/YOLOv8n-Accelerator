"""Generate NPU test program for v3 PingPong_Ctrl: real 3x3 conv on 4x4 input."""
import argparse
from pathlib import Path

OP_CONV   = 0x1
OP_CONFIG = 0x6
OP_DMA_LD = 0x8
OP_DMA_ST = 0x9
OP_HALT   = 0xF


def m(value, bits):
    return value & ((1 << bits) - 1)


def enc_dma(op, dram, sram, size):
    return (m(op, 4) << 124) | (m(dram, 32) << 92) | \
           (m(sram, 32) << 60) | (m(size, 32) << 28)


def enc_config(in_h, in_w, in_c, out_c, stride, pcfg, shift):
    return (m(OP_CONFIG, 4) << 124) | (m(in_h, 16) << 108) | \
           (m(in_w, 16) << 92) | (m(in_c, 16) << 76) | \
           (m(out_c, 16) << 60) | (m(stride, 4) << 56) | \
           (m(pcfg, 10) << 6) | m(shift, 6)


def enc_exec(op, in_a, wgt, out, flags, stride, pad, kernel):
    return (m(op, 4) << 124) | (m(in_a, 32) << 92) | \
           (m(wgt, 32) << 60) | (m(out, 32) << 28) | \
           (m(flags, 12) << 16) | (m(stride, 4) << 12) | \
           (m(pad, 4) << 8) | (m(kernel, 4) << 4)


def enc_halt():
    return m(OP_HALT, 4) << 124


def build():
    # v3 test layer: real 3x3 conv on 4x4 input.
    #   IN=4x4x4, OUT_C=4, K=3, stride=1, pad=0 -> OUT=2x2x4
    #   Mapping: e=2 p=1 q=4 r=1 t=4, OFMAP_COL=2
    dram_in, dram_out, dram_wgt = 0x0000_0000, 0x0020_0000, 0x0100_0000
    sram_in, sram_out, sram_wgt = 0x0000_0000, 0x0000_0800, 0x0038_0000

    in_h = in_w = 4
    in_c = out_c = 4
    kernel = 3
    in_bytes  = in_h * in_w * in_c            # 64
    out_bytes = 2 * 2 * out_c                 # 16 (OUT=2x2)
    # Weight blob: OUT_C * IN_C * 3 * 3 bytes = 4*4*9 = 144 bytes = 36 words.
    wgt_bytes = out_c * in_c * kernel * kernel

    # PE_CONFIG with mapping: p=P_T=4, OFMAP_COL=2 (strip width), q=4
    # p must encode the total number of output channels the PE stores before
    # leaving WEIGHT (= P * T = 1 * 4 = 4).  Using p=1 makes out_ch_num=0
    # so the PE stores only 1 OC and leaves WEIGHT after 3 filter words,
    # causing a permanent stall while PingPong_Ctrl tries to send 36 words.
    p, strip, q = 4, 2, 4
    pcfg = ((p - 1) << 7) | ((strip - 1) << 2) | (q - 1)

    return [
        enc_dma(OP_DMA_LD, dram_wgt, sram_wgt, wgt_bytes),
        enc_dma(OP_DMA_LD, dram_in,  sram_in,  in_bytes),
        enc_config(in_h, in_w, in_c, out_c, 1, pcfg, 0),
        enc_exec(OP_CONV, sram_in, sram_wgt, sram_out, 0, 1, 0, kernel),
        enc_dma(OP_DMA_ST, dram_out, sram_out, out_bytes),
        enc_halt(),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="../Hardware/NPU/TestBench/npu_program.hex")
    args = ap.parse_args()
    prog = build()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(f"{w:032x}" for w in prog) + "\n")
    print(f"wrote {len(prog)} instructions to {out}")
    for i, w in enumerate(prog):
        print(f"  [{i}] {w:032x}")


if __name__ == "__main__":
    main()
