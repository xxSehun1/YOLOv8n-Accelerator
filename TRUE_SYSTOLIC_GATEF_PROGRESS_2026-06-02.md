# True Systolic Gate F Progress - 2026-06-02

## Scope

Control plane remains frozen:

- `Decoder.sv` not modified.
- `DMA_ctrl.sv` not modified.
- `ICache.sv` not modified.
- Compiler / ISS not modified.

This update only changes true datapath/buffer/top integration logic.

## Implemented

1. `IOMap_Buffer.sv`
   - Added NCHW input gather for true PE lane format.
   - Input mode can gather compiler SRAM layout:
     - `SRAM[base + c*H*W + pixel] -> lane[c]`
     - missing channel lanes are filled with `0x80`.
   - Added output scatter back to compiler NCHW layout using SRAM read-modify-write.
   - Kept linear mode for existing handshake tests.

2. `Weight_Buffer.sv`
   - Reworked as raw compact-blob fill plus stream-time repack.
   - Compiler layout:
     - weights: `[OC][IC][KH][KW]` int8
     - bias: `[OC]` int32 after weights
   - PE stream layout:
     - one 32-bit word per `[OC][IC_GROUP4][KH][KW]`.
   - Added bias stream output to `OpsumCollector`.

3. `NPU_top.sv`
   - Wired `Weight_Buffer` bias stream into `OpsumCollector`.
   - Routed IOMap tensor dimensions for NCHW gather/scatter.
   - Added output-drain guard so PingPong waits for both:
     - `OpsumCollector.done`
     - active output `IOMap_Buffer.done`

4. `Line_Buffer.sv`
   - Conv padding output changed from `0x00000000` to `0x80808080`.
   - Reason: ISS pads in signed activation domain with 0, so uint8 hardware input must be zero-point 128.

5. Testbench updates
   - `NPU_top_tb.sv` micro test now uses NCHW input layout.
   - Micro test now has strict golden check, not just HALT smoke.
   - Added `NPU_gate_f_first_conv_tb.sv` for full 640x640 true-systolic first-CONV check.
   - Added Makefile target:
     - `make gate_f_first_conv_full_vcs`

## Passing Evidence

### Micro Gate F Golden Match

Command:

```sh
tcsh -c 'make gate_f_micro_vcs >& gate_f_micro_vcs.log'
```

Result:

```text
[MON][LB_IN] n=5 data=0x81818181
[MON][OPSUM] data=4
[MON][ACT] data=0x84848484
[MON][DRAM_ST] data=0x84848484
word[0] = 0x84848484
word[1] = 0x84848484
MICRO GOLDEN MATCH PASS
```

### Regression

Commands:

```sh
tcsh -c 'make pingpong_buffer_vcs >& pingpong_buffer_vcs.log'
tcsh -c 'make step2_pe_pipeline_vcs >& step2_pe_pipeline_vcs.log'
```

Results:

```text
PingPong_Ctrl_Buffer_tb PASS
LineBuffer_PE_pipeline_tb PASS
```

## Full Gate F Result

Command:

```sh
tcsh -c 'make gate_f_first_conv_full_vcs >& gate_f_first_conv_full_vcs.log'
```

Result:

```text
Timeout waiting HALT pc=3 ppc_st=4 cycle=200000005
```

Key witness:

```text
pc=3
ppc_st=4     // S_IFMAP
ifcnt=96
oy=0
opsum=0
halted=0
```

Interpretation:

- Full input DMA and weight/config entry work.
- Full run reaches first `CONV` at PC=3.
- It deadlocks in `S_IFMAP`.
- The active blocker is true-systolic IFMAP scheduler/tile semantics, not compiler ISA, DMA, NCHW data gather, weight repack, or bias-load plumbing.

## Root Cause

Current `PingPong_Ctrl` still tries to schedule a full 320-output-column row with one diagonal IFMAP stream.

The physical XID field is 5-bit. In the full row case, the IFMAP diagonal tag walks beyond the physical active diagonal range. At `ifmap_count=96`, the tag wraps/re-targets a PE that has already advanced out of IF state, so `GLB_ifmap_ready` stays low and S_IFMAP cannot progress.

## Next Required Fix

Rewrite `PingPong_Ctrl` IFMAP scheduling into a real tile scheduler:

- Use bounded output-column strips that never exceed the active physical XID range.
- Restart or explicitly manage PE IF state at strip boundaries.
- Keep Line_Buffer window consumption aligned with each strip.
- Only then rerun `gate_f_first_conv_full_vcs` for byte-exact comparison against `golden_l0_conv.bin`.

Current sign-off status:

- Micro true-systolic golden: PASS.
- Full first-CONV true-systolic Gate F: NOT PASS, blocked at IFMAP tile scheduler.
