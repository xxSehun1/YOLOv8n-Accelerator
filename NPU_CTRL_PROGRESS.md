# NPU Control Progress

## Current Completion

This repo now has a simulation-focused control/dataflow target for the part owned by `xxSehun`.

Completed:

- Added `Hardware/NPU/NPU_ctrl_top.sv`.
  - Integrates `ICache -> Decoder -> DMA_ctrl -> SRAM`.
  - Replaces the unfinished compute subsystem with `DummyExec`.
  - Keeps the current top-level model: `clk`, `rst`, `start`, `halted`, and DRAM interface.
- Added `Hardware/NPU/Control/DummyExec.sv`.
  - Accepts `CONV`, `POOL`, and `ADD` commands from `Decoder`.
  - Writes deterministic dummy data into the requested output SRAM region.
  - Pulses `exec_done`, so the Decoder can continue through the generated program.
- Updated `Hardware/NPU/Control/DMA_ctrl.sv`.
  - Supports the current compiler/ISS overloaded `DMA_LD` behavior.
  - Handles input load, weight load, concat SRAM copy, and output store.
  - Fixes concat SRAM-copy write data selection so SRAM sources write `sram_rdata`, not `dram_rdata`.
  - Adds debug counters for TB checkpoints.
- Added `Hardware/NPU/TestBench/NPU_ctrl_top_tb.sv`.
  - Loads `Build/npu_program.hex` through `ICache`.
  - Loads `Build/weights.bin` into the TB DRAM weight region.
  - Pulses `start`.
  - Waits for `halted`.
  - Monitors DMA and EXEC traffic.
  - Checks instruction/dataflow counters and output DRAM regions.
- Updated `Hardware/NPU/TestBench/Makefile`.
  - Added `ctrl_full_vcs`.
  - Added `ctrl_full_xrun`.
  - Added generated-program copy step.
- Updated `.gitignore` for simulator artifacts.

Verified with VCS:

```text
pc=127 exec=36 conv=27 pool=3 add=6
input_loaded=1 weight_ld=27 sram_copy=18 store=3

PASS: HALT reached
PASS: PC is parked at HALT instruction
PASS: all generated EXEC ops accepted
PASS: CONV count matches generated ISA
PASS: POOL count matches generated ISA
PASS: ADD count matches generated ISA
PASS: first DMA_LD classified as input DRAM load
PASS: weight DMA_LD count matches generated ISA
PASS: concat DMA_LD SRAM-copy count matches generated ISA
PASS: concat SRAM-copy content was checked
PASS: DMA_ST spill count matches generated ISA
PASS: P3 output base received nonzero dummy data
PASS: P4 output base received nonzero dummy data
PASS: P5 output base received nonzero dummy data
== NPU_ctrl_top_tb PASS ==
```

## What Is Not Complete Yet

The current target verifies control and data exchange, not numeric YOLO correctness.

Not completed:

- Real systolic `CONV`.
- Real residual `ADD`.
- Real `POOL`.
- Bias handling.
- SiLU / activation correctness.
- Quantization correctness.
- Bit-accurate YOLOv8 backbone output.

Current status:

```text
ISA/control/dataflow integration: PASS
real accelerator numerical correctness: NOT YET
```

## Spec Used

The implementation follows the short-term simulation spec agreed in discussion.

Top-level execution model:

```text
TB / external control
  |
  | start pulse
  v
NPU_ctrl_top
  |
  +-- ICache
  |     |
  |     v
  +-- Decoder
        |
        +-- DMA_ctrl
        |
        +-- DummyExec
        |
        +-- SRAM
```

External interface:

```systemverilog
input  logic clk
input  logic rst
input  logic start
output logic halted
DRAM interface
```

Short-term decisions:

- Do not change compiler.
- Do not change generated ISA.
- Use `ICache` with `$readmemh("npu_program.hex")`.
- TB directly pulses `start`.
- No MMIO wrapper yet.
- No external streaming ISA input.
- No CPU-writable instruction memory yet.
- Use dummy compute for unfinished internal submodules.
- RTL/TB must support compiler/ISS `DMA_LD` concat-copy semantics.

Generated ISA used:

```text
Build/npu_program.hex
Build/full_instructions.txt
Build/weights.bin
```

Generated instruction count:

```text
DMA_LD  46
CONFIG  36
CONV    27
ADDCFG   6
ADD      6
POOL     3
DMA_ST   3
HALT     1
```

Required overloaded `DMA_LD` rule:

```text
if dma_is_store == 1:
    DMA_ST: SRAM[dma_sram] -> DRAM[dma_dram]

else if dma_dram >= 0x0100_0000:
    DMA_LD weight: DRAM[dma_dram] -> SRAM[dma_sram]

else if input image has not been loaded yet:
    DMA_LD input: DRAM[dma_dram] -> SRAM[dma_sram]
    mark input_loaded = 1

else:
    DMA_LD concat copy: SRAM[dma_dram] -> SRAM[dma_sram]
```

This matches `Compiler/npu_iss.py` and keeps the compiler unchanged.

## How To Run VCS

Run from the testbench directory:

```bash
cd /home/users/xxSehun/AOC/YOLOv8n-Accelerator/Hardware/NPU/TestBench
tcsh -c 'make ctrl_full_vcs'
```

The Makefile target does:

```text
1. Copy ../../../Build/npu_program.hex to ./npu_program.hex
2. Compile NPU_ctrl_top + Decoder + DMA_ctrl + DummyExec + SRAM + ICache + TB
3. Run ./simv_ctrl_full
4. Print DMA/EXEC monitors and final PASS checks
```

Useful alternate command:

```bash
tcsh -c 'make ctrl_full_xrun'
```

## Why VCS Was Not Found At First

The default shell used by Codex is `bash`. In plain `bash`, `vcs` is not on `PATH`.

This command fails in plain bash:

```bash
which vcs
```

The server config loads EDA tools from `.tcshrc`, so VCS becomes visible only after entering `tcsh` or running a command through `tcsh -c`.

This works:

```bash
tcsh -c 'which vcs'
```

Expected result:

```text
/usr/cad/synopsys/vcs/2023.12/bin/vcs
```

There was also an initial sandbox issue: VCS needs to contact the license server. Running inside the restricted sandbox caused license connection failures. Running the same command with escalated/outside-sandbox permission allowed VCS to compile and run the simulation.

## Current VCS Proof

Command used:

```bash
cd /home/users/xxSehun/AOC/YOLOv8n-Accelerator/Hardware/NPU/TestBench
tcsh -c 'make ctrl_full_vcs'
```

The run completed with:

```text
== NPU_ctrl_top_tb PASS ==
```

The monitor output showed these dataflow stages:

```text
DMA_LD DRAM_INPUT->SRAM
DMA_LD DRAM_WEIGHT->SRAM
EXEC CONV
EXEC ADD
DMA_LD SRAM->SRAM concat-copy
EXEC POOL
DMA_ST SRAM->DRAM
HALT
```

The TB also checks concat-copy content for the first SRAM-to-SRAM DMA:

```text
[CHECKPOINT] concat probe armed src=0x000c8000 dst=0x00190000 src_word=0xd0030000
[CHECKPOINT] concat copy content matched at dst=0x00190000 word=0xd0030000
PASS: concat SRAM-copy content was checked
```
