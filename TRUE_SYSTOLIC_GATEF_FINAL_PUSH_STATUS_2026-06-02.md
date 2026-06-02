# True Systolic Gate F Final Push Status - 2026-06-02

## Current Result

Full 640x640 True Systolic Gate F is not signed off yet.

The current RTL compiles, the micro Gate F regression passes, and the first-CONV compute stream has previously shown bit-exact ACT words at the monitored target point. However, the complete full first-CONV simulation has not reached final `mismatch_count=0` inside the Codex execution environment because long VCS jobs are being terminated around the 30 second tool lifetime.

## RTL Changes Completed

1. `NPU_top.sv`
   - Split SRAM traffic so input IOMap reads and output IOMap writes no longer contend for the same compute SRAM port.
   - DMA still owns SRAM port A when active.
   - During compute, active output IOMap uses SRAM port A.
   - Weight buffer and input IOMap reads use SRAM port B.
   - This fixes the previously observed output scatter loss where input IOMap priority could drop output writes while `oc_act_ready` still accepted data.

2. `IOMap_Buffer.sv`
   - Added NCHW pack/unpack tensor geometry support.
   - Added fast output scatter for word-aligned spatial planes, used by YOLO first-CONV because `OUT_H * OUT_W = 320 * 320`, which is 4-byte aligned.
   - Fast scatter accumulates four spatial bytes into one 32-bit NCHW SRAM word, then writes the full word.
   - Kept RMW fallback for non-word-aligned tensors, needed by the micro Gate F test where the output spatial plane is not 4-byte aligned.

3. `SRAM.sv`
   - SRAM port A now provides active-cycle async read with idle hold.
   - This preserves DMA store's S_RD to S_WR read-hold behavior and lets the unaligned IOMap fallback RMW path work correctly on port A.

## Verification Completed

### Micro Gate F

Command:

```sh
tcsh -c 'make gate_f_micro_vcs >& gate_f_micro_vcs.log'
```

Result:

```text
HALTED at 4915000
== >>>>>>>>>>>  MICRO GOLDEN MATCH PASS  <<<<<<<<<<< ==
```

This proves:

- true datapath reaches HALT;
- output SRAM/DRAM writeback works after the SRAM port split;
- unaligned IOMap fallback still works;
- no regression from the fast output scatter change.

### Full Gate F Attempts

Command forms attempted:

```sh
tcsh -c 'make gate_f_first_conv_full_vcs >& gate_f_first_conv_full_clean.log'
tcsh -c './simv_gate_f_first_conv_full -no_save >& gate_f_first_conv_full_clean.log'
```

Observed progress:

```text
cyc=700000 pc=3 ppc_st=6 tile_base=264 tile_w=1 oy=2 halted=0
```

No `ACT_MISMATCH` was observed before the job was terminated.

The job did not reach final compare because the process was killed by the execution environment before the full simulation could complete. This is not a Gate F pass and not a numerical failure report.

## Previous Full-Run Finding Fixed

Before the SRAM port split, full first-CONV reached HALT but failed final SRAM compare:

```text
mismatch_count=4466
```

The mismatch pattern contained `X` bytes in NCHW output SRAM words. The root cause was output IOMap write traffic being dropped by the SRAM port B priority mux while input IOMap reads were active.

The new port split directly addresses that bug.

## Remaining Blocker

The current scheduler is still correctness-first one-column spatial folding:

```systemverilog
STRIP_MAX = 16'd1
```

This is structurally safe for the current PE/OpsumCollector mapping, but it requires too many cycles for the Codex tool's 30 second VCS process lifetime. The physical PE columns in this RTL are currently used as output-channel lanes through `OpsumCollector`, not as independent spatial columns. Therefore, simply setting `STRIP_MAX=16` would be a false fix unless the GON/OpsumCollector output mapping is also redesigned.

## Next Required Work

To obtain true full 640x640 Gate F sign-off, one of the following must happen:

1. Run the existing full VCS simulation manually on the server outside the Codex process lifetime limit.
2. Re-architect the PE/GON/OpsumCollector mapping so PE columns can safely represent spatial tile columns, then increase spatial tile width.
3. Add a dedicated faster full-run simulation path that preserves the ISA and true datapath but avoids the external tool timeout.

Until a full run reports:

```text
HALT observed
mismatch_count=0
== GATE F FULL FIRST-CONV TRUE SYSTOLIC PASS ==
```

Gate F full sign-off remains open.
