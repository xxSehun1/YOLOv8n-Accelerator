# True Systolic Step 1 Handshake Report - 2026-06-01

## Scope

This report covers Step 1 only: `PingPong_Ctrl` and buffer scheduling handshakes.

Frozen control-plane files were not modified:

- `Hardware/NPU/Control/Decoder.sv`
- `Hardware/NPU/Control/DMA_ctrl.sv`
- `Hardware/NPU/Memory/ICache.sv`
- `Compiler/*`

This is not Gate F and does not claim first-CONV bit-exact systolic compute yet.

## RTL Changes

### PingPong_Ctrl

File: `Hardware/NPU/Control/PingPong_Ctrl.sv`

The old fixed synthetic layer schedule was replaced with an ISA-driven scheduler. The controller now latches the Decoder execution fields and derives transfer counts from the instruction geometry:

- `weight_bytes = OUT_C * IN_C * KERNEL * KERNEL`
- `input_bytes = IN_C * IN_H * IN_W`
- `output_elems = OUT_C * OUT_H * OUT_W` for CONV
- `ifmap_words_total = OUT_H * KERNEL * IN_W` for the current `Line_Buffer` window stream

The controller drives phase-based valid/ready scheduling:

- `S_LOAD_WGT`: starts `Weight_Buffer` SRAM fill
- `S_PE_CONFIG`: starts `IOMap_Buffer` input/output and flushes `Line_Buffer`
- `S_FILTER`: drains filter words under `glb_filter_valid && glb_filter_ready`
- `S_IFMAP`: drains line-buffer window words under `glb_ifmap_valid && glb_ifmap_ready`
- `S_IPSUM`: issues zero ipsum seeds under `glb_ipsum_ready`
- `S_OPSUM`: accepts output partial sums under `glb_opsum_valid && glb_opsum_ready`
- `S_DRAIN`: waits for `oc_done`
- `S_DONE`: pulses `exec_done`

### NPU_top Ready Gate

File: `Hardware/NPU/NPU_top.sv`

The test found one real handshake issue: `Weight_Buffer` can enter readable state one cycle before `PingPong_Ctrl` reaches `S_FILTER`. If `GLB_filter_ready` is already high, the first filter word is consumed during `S_PE_CONFIG`, so `PingPong_Ctrl` only sees 71 of 72 filter words in the test case.

Fix:

```systemverilog
assign wb0_filter_ready = ~wb_sel & GLB_filter_ready & (glb_sel == 2'd1);
assign wb1_filter_ready =  wb_sel & GLB_filter_ready & (glb_sel == 2'd1);
```

This makes the `Weight_Buffer` obey the controller-selected filter phase.

### New Unit Test

File: `Hardware/NPU/TestBench/PingPong_Ctrl_Buffer_tb.sv`

The test instantiates real buffer RTL:

- `PingPong_Ctrl`
- `Weight_Buffer`
- `IOMap_Buffer` for input
- `IOMap_Buffer` for output
- `Line_Buffer`
- simple 1-cycle SRAM model

It uses a small CONV-like ISA configuration:

- `IN_H=5`, `IN_W=5`, `IN_C=4`
- `OUT_C=8`
- `KERNEL=3`, `STRIDE=1`, `PAD=1`
- `FLAGS=0x00b` for bias + SiLU control

Expected transfer counts:

- Weight fill: `8 * 4 * 3 * 3 = 288 bytes = 72 words`
- Input IOMap read: `4 * 5 * 5 = 100 bytes = 25 words`
- Line-buffer windows: `5 * 3 * 5 = 75 words`
- Output elements: `8 * 5 * 5 = 200 bytes`
- Output IOMap writes: `200 / 4 = 50 words`

The test applies artificial backpressure on filter, ifmap, ipsum, opsum, and output-write streams.

## VCS Commands

Step 1 unit test:

```sh
tcsh -c 'cd /home/users/xxSehun/AOC/YOLOv8n-Accelerator/Hardware/NPU/TestBench; make pingpong_buffer_vcs >& pingpong_buffer_vcs.log'
```

Full `NPU_top` elaboration check:

```sh
tcsh -c 'cd /home/users/xxSehun/AOC/YOLOv8n-Accelerator/Hardware/NPU/TestBench; vcs -sverilog -full64 -timescale=1ns/1ps +define+NO_FSDB +incdir+.. +incdir+../Control +incdir+../Buffer +incdir+../Compute +incdir+../Memory +incdir+../PE_Array +incdir+../PE_Array/GIN +incdir+../PE_Array/GON +incdir+../PPU ../NPU_top.sv ../Control/Decoder.sv ../Control/DMA_ctrl.sv ../Control/ConfigLoader.sv ../Control/PingPong_Ctrl.sv ../Control/OpsumCollector.sv ../Buffer/Weight_Buffer.sv ../Buffer/IOMap_Buffer.sv ../Buffer/Line_Buffer.sv ../Memory/SRAM.sv ../Memory/ICache.sv ../PE_Array/PE_array.sv ../PPU/PPU.sv ../PPU/PSUM_acc.sv ../PPU/Add_Qint8.sv -top NPU_top -o simv_npu_top_compile >& npu_top_vcs_compile.log'
```

## Monitor Witness

From `Hardware/NPU/TestBench/pingpong_buffer_vcs.log`:

```text
[MON][65000] wb_fill_start addr=0x00001000 bytes=288
[MON][75000] state 0 -> 1
[MON][825000] state 1 -> 2
[MON][825000] iob_in_start addr=0x00000000 bytes=100
[MON][825000] iob_out_start addr=0x00002000 bytes=200
[MON][825000] lb_flush row_width=5 kernel=3
[MON][835000] state 2 -> 3
[MON][1735000] state 3 -> 4
[MON][3055000] state 4 -> 5
[MON][6055000] state 5 -> 6
[MON][8725000] state 6 -> 7
[MON][8735000] state 7 -> 8
[MON][8755000] oc_done pulse after output buffer done
[MON][8775000] state 8 -> 9
[MON][8785000] state 9 -> 0
```

State mapping:

- `0`: `S_IDLE`
- `1`: `S_LOAD_WGT`
- `2`: `S_PE_CONFIG`
- `3`: `S_FILTER`
- `4`: `S_IFMAP`
- `5`: `S_IPSUM`
- `6`: `S_OPSUM`
- `7`: `S_START_OUT`
- `8`: `S_DRAIN`
- `9`: `S_DONE`

Checked counts:

```text
[CHECK] wb_fill_start_count = 1
[CHECK] iob_in_start_count = 1
[CHECK] iob_out_start_count = 1
[CHECK] lb_flush_count = 1
[CHECK] wb_sram_read_count = 72
[CHECK] iob_input_accept_count = 25
[CHECK] filter_accept_count = 72
[CHECK] ifmap_accept_count = 75
[CHECK] lb_window_accept_count = 75
[CHECK] ipsum_accept_count = 200
[CHECK] opsum_accept_count = 200
[CHECK] output_write_count = 50
[CHECK] oc_layer_start_count = 1
[CHECK] oc_layer_last_count = 1
[CHECK] exec_done_count = 1
== PingPong_Ctrl_Buffer_tb PASS ==
```

VCS simulation report:

```text
Time: 8795000 ps
CPU Time:      0.180 seconds
```

The final `pingpong_buffer_vcs.log` contains no `Warning-`, `Error-`, or `Fatal`.

## Integration Compile Result

`NPU_top` elaboration with the true datapath hierarchy passed cleanly.

From `Hardware/NPU/TestBench/npu_top_vcs_compile.log`:

```text
Top Level Modules:
       NPU_top
CPU time: 1.199 seconds to compile + .314 seconds to elab + .169 seconds to link
```

The final `npu_top_vcs_compile.log` contains no `Warning-`, `Error-`, or `Fatal`.

## Current Conclusion

Step 1 is passed.

The controller-buffer path now has a verified valid/ready schedule for:

- SRAM to `Weight_Buffer`
- SRAM to input `IOMap_Buffer`
- input `IOMap_Buffer` to `Line_Buffer`
- `Line_Buffer` to GLB ifmap stream
- `Weight_Buffer` to GLB filter stream
- GLB ipsum issue phase
- GLB opsum receive phase
- output `IOMap_Buffer` SRAM write stream

The remaining work starts at Step 2:

- prove `Line_Buffer` 3x3 window ordering against expected data values
- prove single PE MAC accumulation with real `w_buf` and `if_reg` pipeline
- then proceed to Gate F first-CONV through the true PE-array datapath
