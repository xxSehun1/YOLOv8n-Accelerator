# True Systolic Gate F Spatial Report - 2026-06-02

## Scope

This report covers Gate F first-CONV verification for the 640x640 YOLOv8n first convolution layer using `NPU_top` and the true PE-array datapath.

This is not the full 142-instruction backbone run. The testbench backdoor-preloads SRAM input and weight data, then executes the compiler-compatible `CONFIG -> CONV -> HALT` instruction sequence through ICache/Decoder/PingPong/PE_array/OpsumCollector/PPU/IOMap/SRAM.

The frozen control plane was not modified: `Decoder.sv`, `DMA_ctrl.sv`, and `ICache.sv` remain untouched in this phase.

## Implemented Changes

- `PingPong_Ctrl.sv`
  - Uses true spatial tiling with `STRIP_MAX = NUMS_PE_COL = 16`.
  - Counts CONV IFMAP as vector window transfers instead of scalar per-column transfers.
  - Counts CONV IPSUM/OPSUM as output-channel vectors instead of `strip_w * out_c` scalar transfers.

- `PE_array.sv`
  - PE columns now act as spatial columns.
  - Added spatial IFMAP vector input: one kernel tap can feed 16 PE columns in one transfer.
  - Added spatial IPSUM broadcast to the active bottom row.
  - Added spatial OPSUM vector output from the active top row.

- `Line_Buffer.sv`
  - Added spatial vector window output.
  - Emits 16 spatial columns per kernel tap in spatial mode.

- `OpsumCollector.sv`
  - Added spatial vector collection.
  - Collects 16 PE-column psums per output channel.
  - Reorders output into IOMap's expected pixel-major/group-major stream.
  - Applies the same quantize + SiLU-LUT behavior as the current PPU path.

- `NPU_top.sv`
  - Connected the vector Line_Buffer -> PE_array IFMAP path.
  - Connected the vector PE_array -> OpsumCollector OPSUM path.
  - Gated the old scalar GON path off during spatial CONV mode.

## Verification Evidence

Command:

```sh
tcsh -c 'make gate_f_first_conv_fast_vec_vcs >& gate_f_first_conv_fast_vec_vcs.log'
```

Result from `Hardware/NPU/TestBench/gate_f_first_conv_fast_vec_vcs.log`:

```text
[TB] HALT observed at 28804805000 cycle=2880476 act_words=409600
[RESULT] mismatch_count=0 output_words=409600 act_words=409600
== GATE F FAST FULL FIRST-CONV TRUE SYSTOLIC PASS ==
CPU Time:    412.940 seconds;       Data structure size:  22.8Mb
```

Gate F functional sign-off status:

- PC reached HALT: PASS
- Full first-CONV output words: 409600 / 409600
- Byte-for-byte compare against `golden_l0_conv.bin`: PASS
- `mismatch_count`: 0

## Runtime Status

The true systolic datapath now passes full 640x640 first-CONV bit-exact verification, but it does not meet the requested 30-second runtime target.

The remaining runtime bottleneck is no longer PE-array compute. The bottleneck is the 32-bit serial IOMap/SRAM stream:

- input tensor preload into Line_Buffer still consumes hundreds of thousands of 32-bit word transfers;
- output tensor writeback still emits 409600 packed activation words through a scalar IOMap/SRAM path.

## Next Required Architecture Work

To meet a strict 30-second VCS target, the next design step is a real burst/banked memory path:

- vector or banked IOMap input reads into Line_Buffer;
- vector or banked IOMap output writes from OpsumCollector;
- matching SRAM multi-bank or vector write/read ports.

Without widening or banking the IOMap/SRAM bandwidth, the PE-array parallelism is functionally correct but the simulation remains dominated by serial memory traffic.
