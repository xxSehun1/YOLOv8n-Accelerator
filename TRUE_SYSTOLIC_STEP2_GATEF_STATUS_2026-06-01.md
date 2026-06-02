# True Systolic Step 2 And Gate F Status - 2026-06-01

## Scope

This report covers:

- Step 2: `Line_Buffer` 3x3 stream verification and single-PE pipeline verification.
- Step 3 pre-check: `NPU_top` true-datapath smoke simulation before attempting full Gate F.

Frozen files were not modified:

- `Hardware/NPU/Control/Decoder.sv`
- `Hardware/NPU/Control/DMA_ctrl.sv`
- `Hardware/NPU/Memory/ICache.sv`
- Python Compiler/ISS files

Gate F is not signed off yet.

## RTL Fixes Made For Step 2

### Line_Buffer

File: `Hardware/NPU/Buffer/Line_Buffer.sv`

The old horizontal emit length was `in_w`. That is insufficient for a PE shift register. A 3-column PE window needs:

```text
emit_cols = (out_w - 1) * stride + kernel
```

Example for `in_w=4, kernel=3, stride=1, pad=1`:

```text
out_w = 4
emit_cols = 4 + 3 - 1 = 6
stream columns = -1, 0, 1, 2, 3, 4
```

This is required to include both left and right padding in the PE's sliding 3-column window.

### PE

File: `Hardware/NPU/PE_Array/PE.sv`

The PE now latches additional config fields:

- `i_config[22:18]`: output-channel count minus one, with old `i_config[9:7]` fallback
- `i_config[17:14]`: horizontal stride, default 1
- `i_config[13:10]`: kernel size, default 3

The IF state now accepts:

- `kernel` tokens for the first output window
- `stride` tokens for each subsequent output window

This is necessary for first YOLOv8n CONV because it has `stride=2`.

### PingPong_Ctrl

File: `Hardware/NPU/Control/PingPong_Ctrl.sv`

The controller's Line_Buffer count was updated to match the fixed stream length:

```text
ifmap_words_total = OUT_H * KERNEL * ((OUT_W - 1) * STRIDE + KERNEL)
```

The PE config packed by `PingPong_Ctrl` now forwards:

- output-channel count minus one
- stride
- kernel
- original `pconfig`

Filter/ipsum/opsum tags were also moved from raw linear count tags to geometry counters:

- filter tag X walks kernel rows
- ipsum/opsum tag X walks output columns

## New Step 2 Test

File: `Hardware/NPU/TestBench/LineBuffer_PE_pipeline_tb.sv`

The test has two independent sections.

### Line_Buffer Stream Check

Configuration:

```text
IN_H=3
IN_W=4
OUT_H=3
KERNEL=3
STRIDE=1
PAD=1
EMIT_COLS=6
```

Expected count:

```text
3 output rows * 3 kernel rows * 6 emitted columns = 54 words
```

The test compares every accepted Line_Buffer output word against a spatial golden model.

### Single-PE Pipeline Check

The test drives one real `PE.sv` instance:

- loads three filter words into `w_buf[0][0..2]`
- feeds a 7-token ifmap stream with left/right padding
- uses `stride=2`
- checks the internal `if_reg[0..2]` window after each shift
- checks three computed opsums against a SystemVerilog golden MAC

## Step 2 VCS Evidence

Command:

```sh
tcsh -c 'cd /home/users/xxSehun/AOC/YOLOv8n-Accelerator/Hardware/NPU/TestBench; make step2_pe_pipeline_vcs >& step2_pe_pipeline_vcs.log'
```

Key monitor/check lines from `Hardware/NPU/TestBench/step2_pe_pipeline_vcs.log`:

```text
[CHECK] LineBuffer input accepts = 12
[CHECK] LineBuffer window accepts = 54
[CHECK] LineBuffer mismatch count = 0
[CHECK] PE w_buf[0][0] = 0xfc03fe01
[CHECK] PE w_buf[0][1] = 0x03ff0102
[CHECK] PE w_buf[0][2] = 0xfe0104fd
[CHECK] PE if_reg[0] first = 0x80808080
[CHECK] PE if_reg[1] first = 0x84838281
[CHECK] PE if_reg[2] first = 0x807f7e7d
[CHECK] PE opsum[0] = 20
[CHECK] PE if_reg[0] stride2 = 0x807f7e7d
[CHECK] PE if_reg[1] stride2 = 0x8f8e8d8c
[CHECK] PE if_reg[2] stride2 = 0x75767778
[CHECK] PE opsum[1] = 55
[CHECK] PE if_reg[0] right = 0x75767778
[CHECK] PE if_reg[1] right = 0x8a898887
[CHECK] PE if_reg[2] right = 0x80808080
[CHECK] PE opsum[2] = 190
== LineBuffer_PE_pipeline_tb PASS ==
CPU Time:      0.170 seconds
```

The final Step 2 log contains no `Warning-`, `Error-`, or `Fatal`.

## Regression Evidence

Step 1 was rerun after the Line_Buffer/PingPong count change.

Command:

```sh
tcsh -c 'cd /home/users/xxSehun/AOC/YOLOv8n-Accelerator/Hardware/NPU/TestBench; make pingpong_buffer_vcs >& pingpong_buffer_vcs.log'
```

Key checks:

```text
[CHECK] filter_accept_count = 72
[CHECK] ifmap_accept_count = 105
[CHECK] lb_window_accept_count = 105
[CHECK] ipsum_accept_count = 200
[CHECK] opsum_accept_count = 200
== PingPong_Ctrl_Buffer_tb PASS ==
```

Legacy `PE_tb` was also rerun after fixing testbench clocking races:

```text
== PE_tb done: 4 passed, 0 failed ==
```

`NPU_top` elaboration also passes with no `Warning-`, `Error-`, or `Fatal`.

## Gate F Pre-Check Result

Before running full 640x640 Gate F, the smaller existing `NPU_top_tb` true-datapath smoke test was rerun.

Result: timeout.

Key heartbeat from `Hardware/NPU/TestBench/npu_top_tb_vcs.log`:

```text
pc=3 halt=0 cfg=1 ppc_st=4 exec_v=1 exec_d=0
ifmap_en=1 lb_ifmap_v=1 ifmap_rdy=0 filter_rdy=0
pe00_st=3 oc_st=2
>> TIMEOUT (no halted in 5 ms sim time)
```

Meaning:

- `pc=3`: currently executing the CONV instruction.
- `ppc_st=4`: `PingPong_Ctrl` is in `S_IFMAP`.
- `pe00_st=3`: PE[0][0] is already in `COMPUTE`.
- `ifmap_rdy=0`: PE array is refusing more ifmap tokens.

This is a real integration blocker. The current `PingPong_Ctrl` still uses coarse phases:

```text
all FILTER -> all IFMAP -> all IPSUM -> all OPSUM
```

But a real PE does not allow that. After enough ifmap tokens for one output window, the PE moves to `COMPUTE` and waits for ipsum. It cannot keep accepting all remaining ifmap tokens for the whole layer. The true schedule must be window-level:

```text
FILTER preload once
then repeat per output window / tile:
  IFMAP tokens for this window
  IPSUM seeds for this window/output channels
  OPSUM drain for this window/output channels
```

Until this scheduler is rewritten, full Gate F cannot pass.

## Additional Gate F Risks Already Identified

These are not theoretical. They must be solved before bit-exact full first-CONV sign-off:

- The compiler weight blob for first CONV is compact int8 plus bias: `0x1F0` bytes. The PE expects 32-bit packed lanes per kernel column. `Weight_Buffer` currently streams raw words and does not repack `IN_C=3` into 4-lane PE filter words.
- `NPU_top` still ties `bias_valid=0`, so CONV bias is not applied by the true PE/PPU path.
- Current `Line_Buffer` output order and GIN diagonal multicast still need a coherent window-level schedule. Step 2 proves the local Line_Buffer and single PE behavior, but the array-level ordering is not signed off.

## Current Conclusion

Step 2 is passed.

Gate F is not passed. The current blocker is the `PingPong_Ctrl` system-level scheduler: it must be changed from whole-layer phase draining into PE-compatible per-window scheduling. Full 640x640 first-CONV bit-exact simulation should not be treated as a valid sign-off target until the smaller `NPU_top_tb` true-datapath smoke test can reach HALT.
