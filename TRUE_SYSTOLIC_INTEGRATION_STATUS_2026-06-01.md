# True Systolic Integration Status

Date: 2026-06-01

## Current Verdict

True Systolic Gate E is not signed off yet.

The previous Gate E result used `NPU_ctrl_top -> ComputeTop`, which is a correctness-first sequential compute path. It proved the arithmetic contract, but it did not prove the true PE-array path.

## Completed In This Step

1. `Hardware/NPU/PPU/SiLU_Qint8.sv`
   - Replaced the empty stub with a fixed 256-entry signed int8 LUT.
   - LUT definition matches the frozen ISS operation:
     `round(q * sigmoid(clip(q, -30, 30)))`.
   - RTL does not use `$exp` or raw math.

2. `Hardware/NPU/TestBench/SiLU_Qint8_tb.sv`
   - Added exhaustive test for all 256 int8 inputs.
   - Also checks `en=0` passthrough.

3. `Hardware/NPU/Control/PingPong_Ctrl.sv`
   - Connected `ppu_silu_en` to latched CONV flags:
     `FLAG_SIGMOID && FLAG_MULTIPLY`.
   - SiLU is no longer tied off in the true PPU path.

4. `Hardware/NPU/NPU_top.sv`
   - Connected previously unconnected `DMA_ctrl` debug outputs to local unused wires.
   - This removes the VCS top-level unconnected-port warning.

## Verification Completed

Command:

```text
tcsh -c 'make silu_qint8_vcs >& silu_qint8_vcs.log'
```

Result:

```text
== SiLU_Qint8_tb PASS: 256 LUT entries and passthrough matched ==
CPU Time: 0.180 seconds
```

Command:

```text
tcsh -c 'vcs -sverilog -full64 -timescale=1ns/1ps +define+NO_FSDB \
  +incdir+.. +incdir+../Control +incdir+../Buffer +incdir+../Compute \
  +incdir+../Memory +incdir+../PE_Array +incdir+../PE_Array/GIN \
  +incdir+../PE_Array/GON +incdir+../PPU \
  ../NPU_top.sv ../Control/Decoder.sv ../Control/DMA_ctrl.sv \
  ../Control/ConfigLoader.sv ../Control/PingPong_Ctrl.sv \
  ../Control/OpsumCollector.sv ../Buffer/Weight_Buffer.sv \
  ../Buffer/IOMap_Buffer.sv ../Buffer/Line_Buffer.sv \
  ../Memory/SRAM.sv ../Memory/ICache.sv ../PE_Array/PE_array.sv \
  ../PPU/PPU.sv ../PPU/PSUM_acc.sv ../PPU/Add_Qint8.sv \
  -top NPU_top -o simv_npu_top_compile >& npu_top_vcs_compile.log'
```

Result:

```text
NPU_top VCS compile/elab passes cleanly.
No Warning-/Error-/Fatal lines remain in npu_top_vcs_compile.log.
```

## Current True Datapath Failure

`NPU_top_tb` now compiles under VCS after changing its DRAM model from `always_ff` to normal testbench `always`.

The simulation does not pass yet. It times out in the first CONV at `pc=3`.

Observed monitor state:

```text
pc=3 halt=0 cfg=1 ppc_st=4 wb_d=1 iob_in_d=0 iob_out_d=0 exec_v=1 exec_d=0
ifmap_en=1 lb_ifmap_v=1 ifmap_rdy=0 filter_rdy=0 pe00_st=3 oc_st=2
```

Decoded meaning:

| Signal | Meaning |
| --- | --- |
| `ppc_st=4` | `PingPong_Ctrl` is in `S_IFMAP` |
| `pe00_st=3` | `PE[0][0]` is already in `COMPUTE` |
| `GLB_ifmap_ready=0` | PE array is not accepting more ifmap |
| `oc_st=2` | `OpsumCollector` is in `S_COLLECT` |

Root cause:

The current `PingPong_Ctrl` and `PE.sv` protocols do not agree on the IFMAP schedule.

`PingPong_Ctrl` is hardcoded for the old MVP geometry:

```text
E=2, P=1, Q=4, R=1, T=4, T_H=1, T_W=1, F_ROW=3, F_COL=3, IFMAP_COL=4, OFMAP_COL=2
```

It waits for a longer `S_IFMAP` stream, but the PE accepts only its small internal IF window and then moves to `COMPUTE`, where it waits for `ipsum`. The controller is still trying to send IFMAP, so the PE array deasserts `GLB_ifmap_ready` and the system deadlocks.

## Larger Architecture Gap

The current `NPU_top` true path is still not capable of the full 142-instruction generated backbone because:

1. `PingPong_Ctrl` is hardcoded to a tiny synthetic CONV shape and does not schedule arbitrary ISA tensor dimensions.
2. `ppu_maxpool_en` and `add_en` are still not connected to a complete POOL/ADD execution flow.
3. Existing `IOMap_Buffer` and `Line_Buffer` stream 32-bit words linearly, but the frozen compiler/ISS memory layout is byte-addressed CHW. Full CONV needs an address/layout adapter that gathers the correct bytes for each PE lane.
4. Full Gate E must instantiate `NPU_top`, not `NPU_ctrl_top`, and must prove that P3/P4/P5 are produced by the PE-array/PPU path.

## Required Next Implementation Work

1. Replace the hardcoded MVP `PingPong_Ctrl` schedule with an ISA-driven scheduler:
   - reads `exec_in_h`, `exec_in_w`, `exec_in_c`, `exec_out_c`, `kernel`, `stride`, `pad`;
   - loops over output channel tile, output y/x, input channel group, kernel y/x;
   - generates deterministic IFMAP/FILTER/IPSUM/OPSUM handshakes.

2. Add a layout adapter between SRAM/Line_Buffer and PE lanes:
   - gathers byte-addressed CHW activations into the lane packing expected by PE input words;
   - handles padding explicitly;
   - supports both `K=1` and `K=3`.

3. Complete true-path POOL and ADD:
   - POOL may use `Maxpool_Qint8` in PPU or a dedicated streaming wrapper;
   - ADD must use `Add_Qint8` with SRAM operand reads and output writes.

4. Add `NPU_top` Gate E testbench:
   - same golden files as the previous Gate E;
   - same final P3/P4/P5 DRAM checks;
   - must monitor PE/GON/GIN/PPU activity so that the result cannot be confused with a `ComputeTop` bypass.

