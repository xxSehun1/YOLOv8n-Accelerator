# NPU Control/Dataflow TB Monitor Notes

Date: 2026-05-31

This document explains how `Hardware/NPU/TestBench/NPU_ctrl_top_tb.sv` verifies the current outer NPU control flow and data path for the generated YOLOv8 backbone ISA.

The purpose of this TB is not to prove real convolution math. Internal compute is still dummy. The target is to prove that the top-level controller can fetch ISA, decode it, dispatch DMA/compute operations, move data through the expected DRAM/SRAM paths, and reach HALT with the expected operation counts.

## Current Test Target

Generated program:

- `Build/npu_program.hex`
- 142 fixed-length 128-bit instructions
- HALT instruction index: `141`

Expected ISA operation count:

| Operation | Expected count | TB check |
|---|---:|---|
| `DMA_LD` | 46 | `monitor_dma_ld_seen == 46` |
| `DMA_ST` | 17 | `debug_store_count == 17`, `monitor_dma_st_seen == 17` |
| `CONV` | 27 | `debug_conv_count == 27` |
| `ADD` | 6 | `debug_add_count == 6` |
| `POOL` | 3 | `debug_pool_count == 3` |
| total dummy exec | 36 | `debug_exec_count == 36` |
| old SRAM-copy DMA_LD | 0 | `debug_sram_copy_count == 0` |
| HALT PC | 141 | `debug_pc == 141` |

## Top-Level Control Flow Being Verified

The TB drives only the minimum external control:

```text
TB
  |
  | clk / rst
  | one-cycle start pulse
  v
NPU_ctrl_top
  |
  +-- ICache reads npu_program.hex
  |
  +-- Decoder fetches 128-bit ISA
  |
  +-- DMA_ctrl handles DMA_LD / DMA_ST
  |
  +-- DummyExec handles CONV / ADD / POOL
  |
  +-- halted asserted after HALT
```

The TB sequence is:

1. Initialize DRAM input memory with deterministic nonzero pattern.
2. Initialize DRAM output/scratch memory to zero.
3. Load `Build/weights.bin` into weight DRAM model.
4. Reset the DUT.
5. Pulse `start` for one cycle.
6. Wait until `halted == 1`.
7. Run final count and dataflow checks.

This matches the short-term execution model: external world does not stream ISA every cycle. The program is preloaded into ICache, and the NPU fetches internally.

## DRAM Memory Model

The TB separates DRAM into three logical regions:

| Region | Base | Size in TB | Purpose |
|---|---:|---:|---|
| input DRAM | `0x0000_0000` | `0x0012_C000` | input image/tensor preload |
| output/scratch DRAM | `0x0020_0000` | 14 MiB | concat staging and final backbone output |
| weight DRAM | `0x0100_0000` | 2 MiB | `weights.bin` preload |

The DRAM model is intentionally simple:

- If `dram_en && !dram_we`, return data from the selected region.
- If `dram_en && dram_we`, write data into the selected region.
- Any write outside the known regions causes `$fatal`.

This catches invalid DMA store addresses early.

## DMA Data Flow Being Verified

The new compiler no longer uses old overloaded `DMA_LD` for SRAM-to-SRAM concat copy.

Current RTL/TB contract:

```text
DMA_LD: DRAM[dma_dram] -> SRAM[dma_sram]
DMA_ST: SRAM[dma_sram] -> DRAM[dma_dram]
```

Concat is now lowered as DRAM staging:

```text
producer SRAM slice
  |
  | DMA_ST
  v
DRAM output/scratch region
  |
  | DMA_LD
  v
concat destination SRAM layout
```

The TB classifies DMA operations with `dma_kind()`:

| Condition | Display label | Meaning |
|---|---|---|
| `dma_is_store == 1` | `DMA_ST SRAM->DRAM` | store SRAM result or concat slice to DRAM |
| `dma_is_store == 0 && dma_dram >= 0x0100_0000` | `DMA_LD DRAM_WEIGHT->SRAM` | load weight blob |
| `dma_is_store == 0 && dma_dram < 0x0020_0000` | `DMA_LD DRAM_INPUT->SRAM` | load model input |
| otherwise | `DMA_LD DRAM_STAGE->SRAM` | reload staged concat/final intermediate data |

Important: this classification is for monitor readability only. The RTL itself does not use this classification to choose source. RTL simply uses `dma_is_store`.

## DMA Monitors

The main DMA monitor triggers when DMA is accepted:

```systemverilog
if (!rst && dut.i_dma.state == 2'd0 && dut.i_dma.dma_valid)
```

At that point the TB:

- increments `monitor_dma_seen`
- increments `monitor_dma_ld_seen` or `monitor_dma_st_seen`
- prints early DMA operations
- always prints stores
- prints DRAM-stage reloads

This provides a readable trace of the major backbone data movement without printing every weight load after the first few.

Example trace pattern from the passing run:

```text
[DMA 1][pc=0]  DMA_LD DRAM_INPUT->SRAM
[DMA 2][pc=1]  DMA_LD DRAM_WEIGHT->SRAM
[EXEC 1][pc=3] CONV
...
[DMA 7][pc=19] DMA_ST SRAM->DRAM
[DMA 9][pc=21] DMA_LD DRAM_STAGE->SRAM
...
HALTED
```

This proves the decoder is sequencing DMA and compute instructions from the generated ISA rather than the TB manually driving each operation.

## Concat Staging Check

This is the most important dataflow check in the current TB.

The TB arms the first concat/staging store when it sees the first `DMA_ST` into output/scratch DRAM:

```text
stage_sram_src  = dma_sram
stage_dram_addr = dma_dram
stage_word      = SRAM[dma_sram >> 2]
```

Then when the DMA reaches done state, the TB checks:

```text
DRAM[stage_dram_addr] == stage_word
```

This proves:

```text
DMA_ST path uses SRAM read data as DRAM write data.
```

Next, when the TB sees a later `DMA_LD` from the same `stage_dram_addr`, it records the destination SRAM address:

```text
stage_sram_dst = dma_sram
```

When that DMA reaches done state, the TB checks:

```text
SRAM[stage_sram_dst] == stage_word
```

This proves:

```text
DMA_LD path uses DRAM read data as SRAM write data.
```

Together, these two checks prove the new concat data path:

```text
SRAM source -> DRAM scratch -> SRAM concat destination
```

They also specifically guard against the old bug class where a copy path writes the wrong read-data bus.

## Compute Monitors

Dummy compute is monitored when `DummyExec` accepts an operation:

```systemverilog
if (!rst && dut.i_dummy_exec.state == 2'd0 && dut.i_dummy_exec.exec_valid)
```

The monitor prints:

- operation kind: `CONV`, `POOL`, `ADD`
- program counter
- output SRAM address
- input height
- input width
- output channels
- stride
- padding
- kernel size

Example:

```text
[EXEC 1][pc=3] CONV out=0x0012c000 H=640 W=640 OC=16 stride=2 pad=1 kernel=3
[EXEC 6][pc=18] ADD  out=0x00000000 H=160 W=160 OC=16 stride=1 pad=0 kernel=1
[EXEC 33][pc=124] POOL out=0x00000000 H=20 W=20 OC=128 stride=1 pad=2 kernel=5
```

This proves that:

- `CONFIG` state is latched and consumed by the following compute op.
- `CONV`, `ADD`, and `POOL` are decoded and dispatched.
- The top-level flow does not deadlock while dummy compute is active.
- The generated backbone reaches expected spatial scales.

It does not prove real convolution, pooling, add, quantization, SiLU, or systolic-array behavior.

## HALT and Final Output Checks

After `halted` is observed, the TB checks:

```text
debug_pc == 141
debug_exec_count == 36
debug_conv_count == 27
debug_pool_count == 3
debug_add_count == 6
monitor_dma_ld_seen == 46
debug_weight_load_count == 27
debug_sram_copy_count == 0
debug_store_count == 17
```

The TB also checks that the final P3/P4/P5-like output addresses received nonzero dummy data:

| Output | DRAM absolute address | TB array offset |
|---|---:|---:|
| P3-like | `0x003F_4000` | `0x001F_4000` |
| P4-like | `0x004B_C000` | `0x002B_C000` |
| P5-like | `0x0054_5800` | `0x0034_5800` |

The TB uses offsets because `dram_out_mem[0]` corresponds to absolute DRAM address `DRAM_OUTPUT_BASE = 0x0020_0000`.

These final checks prove that the top-level flow stores final backbone outputs to the generated ISA's current output addresses.

## What This TB Proves

This TB currently proves:

- ICache preload and internal fetch flow works.
- One-cycle external `start` is enough to launch the program.
- Decoder can sequence through the generated 142-instruction program.
- `CONFIG` information reaches dummy compute.
- `CONV`, `ADD`, and `POOL` dispatch counts match the generated backbone.
- `DMA_LD` works as DRAM-to-SRAM.
- `DMA_ST` works as SRAM-to-DRAM.
- New concat lowering works through DRAM staging.
- Old overloaded SRAM-to-SRAM `DMA_LD` is not used.
- HALT is reached and held.
- Final output regions receive dummy data.

## What This TB Does Not Prove Yet

This TB does not prove:

- Real YOLOv8 backbone numerical correctness.
- Real systolic-array scheduling.
- Real line buffer behavior.
- Real ping-pong buffer hazard freedom.
- Real PPU, bias, SiLU, quantization, or shift correctness.
- Cycle-level performance.
- AXI/NoC/protocol correctness.
- CPU MMIO register behavior.
- Runtime writable instruction memory.

Those belong to later integration stages after the external control/data path contract is stable.

## How To Run

From the testbench directory:

```sh
cd /home/users/xxSehun/AOC/YOLOv8n-Accelerator/Hardware/NPU/TestBench
tcsh -c 'make ctrl_full_vcs'
```

The `tcsh` wrapper is needed on this server because the EDA environment sets VCS paths and license variables through the tcsh startup setup.

Expected final PASS summary:

```text
pc=141 exec=36 conv=27 pool=3 add=6
dma_ld=46 dma_st=17 input_loaded=1 weight_ld=27 sram_copy=0 store=17
PASS: concat staging DMA_ST content was checked
PASS: concat staging DMA_LD content was checked
PASS: P3-like final output received nonzero dummy data
PASS: P4-like final output received nonzero dummy data
PASS: P5-like final output received nonzero dummy data
== NPU_ctrl_top_tb PASS ==
```
