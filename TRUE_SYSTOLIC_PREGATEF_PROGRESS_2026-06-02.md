# True Systolic Pre-Gate F Progress - 2026-06-02

## Scope

This update focuses on the approved pre-Gate F re-architecture work:

- Keep the frozen control plane intact: `Decoder.sv`, `DMA_ctrl.sv`, `ICache.sv`, Compiler/ISS were not modified.
- Move `PingPong_Ctrl` away from the old all-IFMAP/all-COMPUTE style schedule.
- Prove the true `NPU_top -> GIN/GON -> PE_array -> OpsumCollector -> PPU -> IOMap` path can run a micro smoke without deadlock.

## RTL Changes

### `Hardware/NPU/Control/PingPong_Ctrl.sv`

- Reworked CONV scheduling into interleaved row/tile phases:
  - `FILTER`
  - per output row/tile: `IFMAP -> IPSUM -> OPSUM`
  - output drain
- Added row/tile counters for IFMAP, IPSUM, and OPSUM instead of one monolithic full-layer IFMAP phase.
- Added `S_OPSUM` as `glb_sel = 2'd3`, so OPSUM drain is an explicit scheduled phase.
- Changed IFMAP tag policy for the current shared-config diagonal PE mapping.
  - Useful IFMAP tokens use diagonal tag walk.
  - Extra Line_Buffer tokens are drained with no-op tag `30`, not `31`, because `31` is used by inactive PEs in `shared_config.hex`.

### `Hardware/NPU/NPU_top.sv`

- Gated PE-array OPSUM valid/ready into `OpsumCollector` only during `glb_sel == 2'd3`.
- This prevents stale or early GON outputs from being consumed outside the scheduled OPSUM phase.

### `Hardware/NPU/Buffer/Line_Buffer.sv`

- Updated Line_Buffer to emit complete 3x3 window token sequences with valid/ready backpressure.
- The testbench now checks the emitted window stream against an expected software reconstruction.

### Testbench / Makefile

- Added `Hardware/NPU/TestBench/npu_program_gatef_micro.hex`.
- Added `make gate_f_micro_vcs`.
- Updated `NPU_top_tb.sv` to label this as a true-systolic micro smoke, not bit-exact Gate F.

## Verification Evidence

### Step 2 Regression

Command:

```sh
tcsh -c 'make step2_pe_pipeline_vcs >& step2_pe_pipeline_vcs.log'
```

Result:

- `LineBuffer window accepts = 108`
- `LineBuffer mismatch count = 0`
- Single PE `w_buf`, `if_reg`, and MAC checks passed.
- VCS CPU time: `0.170 seconds`
- Final: `LineBuffer_PE_pipeline_tb PASS`

### PingPong/Buffer Handshake

Command:

```sh
tcsh -c 'make pingpong_buffer_vcs >& pingpong_buffer_vcs.log'
```

Result:

- `filter_accept_count = 72`
- `ifmap_accept_count = 225`
- `ipsum_accept_count = 200`
- `opsum_accept_count = 200`
- `output_write_count = 50`
- `exec_done_count = 1`
- VCS CPU time: `0.180 seconds`
- Final: `PingPong_Ctrl_Buffer_tb PASS`

### True-Systolic Micro Gate F Smoke

Command:

```sh
tcsh -c 'make gate_f_micro_vcs >& gate_f_micro_vcs.log'
```

Result:

- Program: 3x4x4 input, 3x3 CONV, 4 output channels, 1x2 output.
- DUT top: `NPU_top`
- Path includes `GIN/GON`, `PE_array`, `OpsumCollector`, `PPU`, and IOMap output path.
- `HALTED at 4165000 ps`
- Simulation finished at `4265000 ps`
- VCS CPU time: `0.200 seconds`
- Final: `MICRO SMOKE HALT PASS`

## Current Conclusion

The true systolic path no longer deadlocks on the micro smoke. This proves the revised scheduler can drive the real PE-array hierarchy through FILTER, IFMAP, IPSUM, OPSUM, output drain, DMA_ST, and HALT.

This is not Gate F bit-exact sign-off yet. The current micro output is not golden-matched; it is a control-flow/deadlock smoke only.

## Remaining Gate F Blockers

- Weight_Buffer compact INT8 to PE-lane repacking is still not implemented for compiler blobs such as first CONV with `IN_C=3`.
- Bias path is still not wired; `NPU_top` currently ties `bias_valid = 0` and `bias_word = 0`.
- IFMAP data ordering is currently a diagonal smoke schedule with no-op drain tokens. It prevents deadlock, but still needs the real data-aligned diagonal stream to become bit-exact.
- PE row/tile restart semantics are not solved for multi-output-row convolution. The current micro smoke uses one output row to avoid that unresolved row-transition problem.

## Sign-Off Status

- Step 2: PASS
- PingPong/buffer handshake after re-architecture: PASS
- Micro true-systolic HALT/no-deadlock smoke: PASS
- Full Gate F bit-exact first CONV: NOT PASSED YET
