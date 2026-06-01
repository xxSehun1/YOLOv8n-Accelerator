# Gate C First CONV Report - 2026-05-31

## Goal

This report records the fix for the Gate C simulation bottleneck and the current verification result.

Gate C target:

- Remove `DummyExec` from the first real CONV verification path.
- Execute the first YOLOv8 backbone CONV with RTL compute modules.
- Compare RTL output byte-for-byte against software golden output.
- Avoid full 640x640 bring-up until the compute datapath is proven on a tiny image.

## Bottleneck Found

The previous `ComputeTop.sv` implementation used a software-like `always_comb` loop to derive CONV coordinates. The costly pieces were:

- per-cycle variable divide `/`
- per-cycle variable modulo `%`
- repeated variable multiplies for address generation
- multi-read combinational access into the large SRAM mirror

For the full first layer, this made VCS spend nearly all runtime inside address/math evaluation before useful progress was visible. The full-size run was stopped and Gate C was moved to a tiny deterministic test first.

## RTL Changes

### `Hardware/NPU/Compute/ConvAddrGen.sv`

Added a nested-counter CONV address generator.

Counter order:

```text
kx -> ky -> ic -> ow -> oh -> oc
```

Outputs:

- `act_addr`
- `wgt_addr`
- `out_addr`
- `is_pad_zero`
- `pixel_done`
- debug counters: `dbg_oc/dbg_oh/dbg_ow/dbg_ic/dbg_ky/dbg_kx/dbg_out_h/dbg_out_w`

This removes per-MAC divide/modulo from the hot simulation path.

### `Hardware/NPU/Compute/ComputeTop.sv`

Replaced the old CONV path with a serial correctness-first datapath:

- one MAC step per cycle
- instantiates `ConvAddrGen`
- instantiates `ConvMacUnit`
- instantiates `QuantizeUnit`
- instantiates `ActivationUnit`
- writes computed output bytes back into SRAM
- keeps a DMA snoop SRAM mirror so compute can read data loaded by DMA

Current integration scope:

- `CONV`: implemented for Gate C
- non-CONV `exec_op`: intentionally fatal in this Gate C compute path

### `Hardware/NPU/TestBench/NPU_first_conv_tb.sv`

Updated first-CONV TB to use tiny deterministic vectors:

- input: `Build/input_tiny16_seed0.bin`
- golden: `Build/golden_l0_tiny16_conv.bin`
- output size: `8 * 8 * 16 = 1024 bytes`

The TB verifies:

- first DMA input load copied DRAM to SRAM
- first DMA weight load copied DRAM to SRAM
- first decoded compute op is CONV
- no POOL/ADD/DMA_ST happens before first CONV completes
- output SRAM matches golden byte-for-byte

### `Compiler/generate_gatec_vectors.py`

Added tiny first-CONV vector generation.

Tiny program:

```text
pc=0 DMA_LD input  DRAM 0x00000000 -> SRAM 0x00000000, size 0x00000300
pc=1 DMA_LD weight DRAM 0x01000000 -> SRAM 0x00380000, size 0x000001f0
pc=2 CONFIG H=16 W=16 IC=3 OC=16 stride=2 pcfg=0x07e shift=0x0a
pc=3 CONV IN=0x00000000 WGT=0x00380000 OUT=0x0012c000 FLAGS=0x00b STRIDE=2 PAD=1 KERNEL=3
pc=4 HALT
```

Generated file hashes:

```text
Build/input_tiny16_seed0.bin        4fca05f1d7f9c355405c546942e1983df61017aea651b32d047a8c1a4b96c4e5
Build/golden_l0_tiny16_conv.bin     bb8c3d0f1203f1a8f956c2221e452b0a48255d53dff804500befc283c93e2103
Build/full_instructions_gatec_tiny.txt 55a785dc5d4f38074b15d555d96e6b3d9edca66ae4d81dc995b38db241e8a710
Build/npu_program_gatec_tiny.hex    15abedb9278948be47121dea1569d1a746bc51a8f01d2f062e08430dfe3c85e5
```

## Verification Commands

Run from `Hardware/NPU/TestBench`:

```sh
tcsh -c 'make primitive_units_vcs >& primitive_units_vcs.log'
tcsh -c 'make gate_c_first_conv_vcs >& gate_c_first_conv_vcs.log'
```

## Gate B Result

Primitive compute unit regression passed.

Observed summary:

```text
== QuantizeUnit_tb PASS: 73 checks ==
== ActivationUnit_tb PASS: 778 checks ==
== AddUnit_tb PASS: 584 checks ==
== PoolCompareUnit_tb PASS: 10 checks ==
== ConvMacUnit_tb PASS: 6 checks ==
==== Primitive compute unit VCS regression PASS ====
```

## Gate C Monitor Witness

Source log:

```text
Hardware/NPU/TestBench/gate_c_first_conv_vcs.log
```

Important monitor evidence:

```text
[TB] loaded 768 input bytes
[TB] loaded 1277680 weight bytes
[TB] loaded 1024 golden L0 bytes
== NPU_first_conv_tb: Gate C tiny first real CONV bit-exact check ==
[TB] start pulsed at 105000
[DECODE pc=0] DMA_LD dram=0x00000000 sram=0x00000000 size=0x00000300
[DMA][pc=0]  DMA_LD DRAM_INPUT->SRAM dram=0x00000000 sram=0x00000000 size=0x00000300
[DECODE pc=1] DMA_LD dram=0x01000000 sram=0x00380000 size=0x000001f0
[DMA][pc=1] DMA_LD DRAM_WEIGHT->SRAM dram=0x01000000 sram=0x00380000 size=0x000001f0
[DECODE pc=2] CONFIG H=16 W=16 IC=3 OC=16 stride=2 pcfg=0x07e shift=0x0a
[DECODE pc=3] CONV in=0x00000000 wgt=0x00380000 out=0x0012c000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=16 W=16 IC=3 OC=16 pcfg=0x07e shift=0x0a)
[EXEC_ACCEPT][pc=3] first CONV out=0x0012c000 H=16 W=16 OC=16 stride=2 pad=1 kernel=3
[COMPUTE][pc=3] start nested CONV addrgen in=0x00000000 wgt=0x00380000 out=0x0012c000
[COMPUTE][pc=3] wrote through output byte offset 0x000000ff oc=3 oh=7 ow=7
[COMPUTE][pc=3] wrote through output byte offset 0x000001ff oc=7 oh=7 ow=7
[COMPUTE][pc=3] wrote through output byte offset 0x000002ff oc=11 oh=7 ow=7
[COMPUTE][pc=3] wrote through output byte offset 0x000003ff oc=15 oh=7 ow=7
[EXEC_DONE][pc=3] first CONV real output complete
[TB] first CONV completed at 316325000
```

Final checks:

```text
PASS: exactly one EXEC op completed
PASS: debug opcode alias checked through first CONV
PASS: first EXEC was CONV
PASS: no POOL executed
PASS: no ADD executed
PASS: input DMA_LD was observed
PASS: one weight DMA_LD was observed
PASS: no DMA_ST before first CONV completes
PASS: input first word copied DRAM->SRAM
PASS: input last word copied DRAM->SRAM
PASS: weight first word copied DRAM->SRAM
PASS: weight last word copied DRAM->SRAM
PASS: Gate C tiny first CONV output byte-for-byte matches golden_l0_tiny16_conv.bin
== NPU_first_conv_tb GATE C PASS ==
```

VCS runtime:

```text
Time: 316325000 ps
CPU Time: 0.210 seconds
Data structure size: 4.2Mb
```

## Current Status

Gate C tiny first real CONV is passed.

This proves:

- Decoder fetches and decodes the tiny first-CONV ISA correctly.
- DMA loads input and first-layer weights into SRAM.
- `ComputeTop` accepts CONV through the real exec interface.
- `ConvAddrGen` traverses the output tensor and kernel coordinates correctly for the tiny case.
- MAC, quantization, activation, packing, and SRAM writeback produce byte-exact output against the frozen software golden.

## Remaining Work

This is not yet the full YOLOv8 backbone.

Next engineering steps:

1. Extend `ComputeTop` from CONV-only to POOL and ADD.
2. Add Gate C variants for more CONV shapes before returning to full 640x640.
3. Add Gate D layer-by-layer backbone execution.
4. Only after layer-level confidence, retry full-size execution.
