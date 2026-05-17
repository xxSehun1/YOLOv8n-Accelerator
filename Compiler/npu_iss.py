"""
npu_iss.py — Instruction-Set Simulator for the YOLOv8n NPU.

Functionally executes the emitted program (full_instructions.txt) together
with weights.bin and an input image, modelling:

    DMA_LD / DMA_ST   byte-exact block copy
    CONV              INT8 conv + int32 bias + requant right-shift + activation
    POOL              max-pooling
    ADD               residual add with per-operand right-shift
    CONFIG / ADDCFG   latch dimensions / shifts

Activations are uint8 with zero-point 128 (matches PE.sv `ifmap - 128` and
PPU.sv `+ 128`). Weights are signed int8, bias is int32.

Usage:
    python npu_iss.py [instr_file] [weights_file] [--input input.npy]
"""
import sys
import numpy as np

SRAM_SIZE        = 4 * 1024 * 1024
DRAM_SIZE        = 32 * 1024 * 1024
DRAM_WEIGHT_BASE = 0x0100_0000
ZP               = 128

FLAG_SIGMOID  = 0x1
FLAG_MULTIPLY = 0x2
FLAG_RELU     = 0x4
FLAG_BIAS     = 0x8


# Arithmetic kernels (the NPU's exact integer behaviour).

def conv_int8(x_s, w, bias, stride, pad, shift, flags):
    """x_s: (IC,IH,IW) signed ifmap (byte-128). w: (OC,IC,KH,KW) int8.
       Returns (OC,OH,OW) uint8 output (zp=128)."""
    IC, IH, IW   = x_s.shape
    OC, _, KH, KW = w.shape
    xp = np.pad(x_s, ((0, 0), (pad, pad), (pad, pad))).astype(np.int64)
    OH = (IH + 2 * pad - KH) // stride + 1
    OW = (IW + 2 * pad - KW) // stride + 1

    acc = np.zeros((OC, OH, OW), np.int64)
    for kh in range(KH):
        for kw in range(KW):
            patch = xp[:, kh:kh + stride * OH:stride, kw:kw + stride * OW:stride]
            acc += np.einsum('oi,ihw->ohw',
                             w[:, :, kh, kw].astype(np.int64), patch)
    if bias is not None:
        acc += bias.astype(np.int64)[:, None, None]

    q = acc >> shift                                  # arithmetic right shift
    q = _activation(q, flags)
    q = np.clip(q, -128, 127)
    return (q + ZP).astype(np.uint8)


def _activation(q, flags):
    if (flags & FLAG_SIGMOID) and (flags & FLAG_MULTIPLY):     # SiLU
        s = 1.0 / (1.0 + np.exp(-np.clip(q, -30, 30)))
        return np.round(q * s).astype(np.int64)
    if flags & FLAG_RELU:
        return np.maximum(q, 0)
    return q


def pool_max(x_s, kernel, stride, pad):
    """Max-pool on the signed domain; pad with -128 (matches Maxpool_Qint8)."""
    IC, IH, IW = x_s.shape
    xp = np.pad(x_s, ((0, 0), (pad, pad), (pad, pad)),
                constant_values=-128).astype(np.int64)
    OH = (IH + 2 * pad - kernel) // stride + 1
    OW = (IW + 2 * pad - kernel) // stride + 1
    out = np.full((IC, OH, OW), -128, np.int64)
    for kh in range(kernel):
        for kw in range(kernel):
            patch = xp[:, kh:kh + stride * OH:stride, kw:kw + stride * OW:stride]
            out = np.maximum(out, patch)
    return (out + ZP).astype(np.uint8)


def add_int8(a_s, b_s, lhs_shift, rhs_shift):
    """Residual add: out = sat( (a>>>LHS) + (b>>>RHS) ) on the signed domain."""
    s = (a_s.astype(np.int64) >> lhs_shift) + (b_s.astype(np.int64) >> rhs_shift)
    s = np.clip(s, -128, 127)
    return (s + ZP).astype(np.uint8)


# Instruction-set simulator.

class NPU_ISS:
    def __init__(self, weight_bytes):
        self.sram = np.zeros(SRAM_SIZE, np.uint8)
        self.dram = np.zeros(DRAM_SIZE, np.uint8)
        self.dram[DRAM_WEIGHT_BASE:DRAM_WEIGHT_BASE + len(weight_bytes)] = \
            np.frombuffer(weight_bytes, np.uint8)
        self.cfg       = {}
        self.lhs_shift = 0
        self.rhs_shift = 0
        self.input_done = False
        self.layers    = []          # (idx, op, out_addr, ndarray) per compute op

    # -- SRAM <-> tensor helpers (NCHW, channel-major, uint8 zp=128) ----------
    def _read_signed(self, addr, c, h, w):
        flat = self.sram[addr:addr + c * h * w].astype(np.int64)
        return flat.reshape(c, h, w) - ZP

    def _write(self, addr, arr):
        self.sram[addr:addr + arr.size] = arr.flatten()

    # -- main loop -----------------------------------------------------------
    def run(self, instrs, input_image):
        self.dram[:input_image.size] = input_image.astype(np.uint8).flatten()
        for idx, line in enumerate(instrs):
            f  = _fields(line)
            op = f.get('OP', '')
            if   op == 'CONFIG': self.cfg = f
            elif op == 'ADDCFG':
                self.lhs_shift = int(f['LHS'], 16)
                self.rhs_shift = int(f['RHS'], 16)
            elif op == 'DMA_LD': self._dma_ld(f)
            elif op == 'DMA_ST': self._dma_st(f)
            elif op == 'CONV':   self._conv(idx, f)
            elif op == 'POOL':   self._pool(idx, f)
            elif op == 'ADD':    self._add(idx, f)
            elif op == 'HALT':   break

    # -- DMA -----------------------------------------------------------------
    def _dma_ld(self, f):
        dram = int(f['DRAM'], 16); sram = int(f['SRAM'], 16)
        size = int(f['SIZE'], 16)
        if dram >= DRAM_WEIGHT_BASE:                       # weight load
            self.sram[sram:sram + size] = self.dram[dram:dram + size]
        elif not self.input_done:                          # input image load
            self.sram[sram:sram + size] = self.dram[dram:dram + size]
            self.input_done = True
        else:                                              # concat SRAM->SRAM copy
            self.sram[sram:sram + size] = self.sram[dram:dram + size]

    def _dma_st(self, f):
        dram = int(f['DRAM'], 16); sram = int(f['SRAM'], 16)
        size = int(f['SIZE'], 16)
        self.dram[dram:dram + size] = self.sram[sram:sram + size]

    # -- compute -------------------------------------------------------------
    def _conv(self, idx, f):
        in_c = int(self.cfg['IN_C']); in_h = int(self.cfg['IN_H'])
        in_w = int(self.cfg['IN_W']); out_c = int(self.cfg['OUT_C'])
        shift  = int(self.cfg['SHIFT'], 16)
        stride = int(f['STRIDE']); pad = int(f['PAD']); k = int(f['KERNEL'])
        flags  = int(f['FLAGS'], 16)
        in_a   = int(f['IN'], 16); wgt = int(f['WGT'], 16); out = int(f['OUT'], 16)

        x_s = self._read_signed(in_a, in_c, in_h, in_w)
        wn  = out_c * in_c * k * k
        w   = self.sram[wgt:wgt + wn].astype(np.int8).reshape(out_c, in_c, k, k)
        bias = None
        if flags & FLAG_BIAS:
            bb = self.sram[wgt + wn:wgt + wn + out_c * 4]
            bias = bb.view(np.int32).copy()

        y = conv_int8(x_s, w, bias, stride, pad, shift, flags)
        self._write(out, y)
        self.layers.append((idx, 'CONV', out, y))

    def _pool(self, idx, f):
        in_c = int(self.cfg['IN_C']); in_h = int(self.cfg['IN_H'])
        in_w = int(self.cfg['IN_W'])
        stride = int(f['STRIDE']); pad = int(f['PAD']); k = int(f['KERNEL'])
        in_a = int(f['IN'], 16); out = int(f['OUT'], 16)

        x_s = self._read_signed(in_a, in_c, in_h, in_w)
        y   = pool_max(x_s, k, stride, pad)
        self._write(out, y)
        self.layers.append((idx, 'POOL', out, y))

    def _add(self, idx, f):
        in_c = int(self.cfg['IN_C']); in_h = int(self.cfg['IN_H'])
        in_w = int(self.cfg['IN_W'])
        in_a = int(f['IN'], 16); wgt = int(f['WGT'], 16); out = int(f['OUT'], 16)

        a_s = self._read_signed(in_a, in_c, in_h, in_w)
        b_s = self._read_signed(wgt,  in_c, in_h, in_w)
        y   = add_int8(a_s, b_s, self.lhs_shift, self.rhs_shift)
        self._write(out, y)
        self.layers.append((idx, 'ADD', out, y))


def _fields(line):
    out = {}
    for part in line.split('|'):
        if ':' in part:
            k, v = part.split(':', 1)
            out[k.strip()] = v.strip()
    return out


# Entry point.

def main():
    instr_file  = "../Build/full_instructions.txt"
    weight_file = "../Build/weights.bin"
    input_file  = None
    args = sys.argv[1:]
    for a in args:
        if a.endswith('.txt'):  instr_file  = a
        elif a.endswith('.bin'): weight_file = a
        elif a.startswith('--input='): input_file = a.split('=', 1)[1]

    instrs = [ln.strip() for ln in open(instr_file) if '|' in ln]
    weights = open(weight_file, 'rb').read()

    if input_file:
        img = np.load(input_file)
    else:
        rng = np.random.default_rng(0)
        img = rng.integers(0, 256, size=3 * 640 * 640, dtype=np.uint8)
        print("No --input given: using a fixed random image (seed 0)")

    iss = NPU_ISS(weights)
    iss.run(instrs, img)

    print(f"Executed {len(instrs)} instructions, "
          f"{len(iss.layers)} compute layers")
    for i, (idx, op, addr, arr) in enumerate(iss.layers):
        print(f"  L{i:2d} line {idx:3d} {op:5s} OUT=0x{addr:06X} "
              f"shape={arr.shape} "
              f"min={int(arr.min())} max={int(arr.max())} "
              f"mean={arr.mean():.1f}")

    np.savez("../Build/iss_layers.npz",
             **{f"L{i}_{op}": arr for i, (idx, op, a, arr) in enumerate(iss.layers)})
    print("Per-layer feature maps dumped to ../Build/iss_layers.npz")


if __name__ == "__main__":
    main()
