# YOLOv8 Backbone Outer-Control Verification Report

Date: 2026-05-31

This report records the implementation and verification completed after reviewing:

```text
YOLO_BACKBONE_STATUS_AND_VERIFICATION_PLAN_2026-05-31.md
```

Scope:

```text
Outer NPU control/dataflow only.
Real CONV/POOL/ADD arithmetic is still represented by DummyExec.
```

## Implemented In This Pass

- Added strict Decoder opcode unit test:
  ```text
  Hardware/NPU/TestBench/Decoder_opcode_tb.sv
  ```
- Added standalone DMA_ctrl data-path unit test:
  ```text
  Hardware/NPU/TestBench/DMA_ctrl_unit_tb.sv
  ```
- Added Makefile targets:
  ```text
  decoder_opcode_vcs
  dma_ctrl_unit_vcs
  first_conv_vcs
  first_conv_vcs_fsdb
  ctrl_full_vcs
  ctrl_full_vcs_fsdb
  ```
- Fixed Decoder unsupported-opcode behavior:
  ```text
  unsupported opcode advances PC to the next instruction
  unsupported opcode asserts no DMA/EXEC command
  unsupported opcode cannot deadlock
  ```
- Fixed Decoder HALT PC behavior after the unsupported-opcode change:
  ```text
  HALT now parks PC at the HALT instruction
  HALT is not treated as unsupported default
  ```
- Added Decoder protocol assertions:
  ```text
  DMA command payload remains stable while dma_valid && !dma_done
  EXEC command payload remains stable while exec_valid && !exec_done
  ```
- Regenerated clean markdown witness logs:
  ```text
  decoder_opcode_log.md
  dma_ctrl_unit_log.md
  first_conv_log.md
  log.md
  ```
- Regenerated waveform files:
  ```text
  Hardware/NPU/TestBench/npu_first_conv.fsdb
  Hardware/NPU/TestBench/npu_ctrl_top.fsdb
  ```

## Verification Run

All commands were run from:

```text
Hardware/NPU/TestBench
```

using:

```text
tcsh -c '<make target> |& tee <log>'
```

### Level 1: Decoder Opcode Unit Test

Command:

```text
make decoder_opcode_vcs
```

Result:

```text
PASS
```

Checked:

- DMA_LD drives DMA command only
- DMA_ST drives DMA command only
- CONFIG latches shape/config for later compute op
- ADDCFG latches lhs/rhs shifts for later ADD
- CONV drives `exec_valid` and `exec_op=0`
- POOL drives `exec_valid` and `exec_op=1`
- ADD drives `exec_valid` and `exec_op=2`
- HALT asserts `halted` and keeps PC parked
- unsupported CONCAT/OTHER/BIAS/0xE advances to next instruction and does not deadlock

Witness:

```text
decoder_opcode_log.md
Hardware/NPU/TestBench/decoder_opcode_vcs.log
```

### Level 2: DMA_ctrl Data-Path Unit Test

Command:

```text
make dma_ctrl_unit_vcs
```

Result:

```text
PASS
```

Checked:

- small DMA_LD reads DRAM and writes SRAM
- weight DMA_LD reads DRAM weight region and writes SRAM
- small DMA_ST reads SRAM and writes DRAM
- DRAM staging pair works:
  ```text
  SRAM -> DRAM by DMA_ST
  DRAM -> SRAM by DMA_LD
  ```
- first/middle/last copied words match
- address sequence is word-exact
- `widx` reaches expected word count
- `dma_done` is a single observed completion event
- no old overloaded SRAM-copy DMA_LD is used

Witness:

```text
dma_ctrl_unit_log.md
Hardware/NPU/TestBench/dma_ctrl_unit_vcs.log
```

### Level 3: First CONV Outer-Flow Smoke

Command:

```text
make first_conv_vcs
```

Result:

```text
PASS
```

Checked:

- input DMA_LD:
  ```text
  DRAM 0x00000000 -> SRAM 0x00000000
  ```
- first weight DMA_LD:
  ```text
  DRAM 0x01000000 -> SRAM 0x00380000
  ```
- CONFIG for first CONV:
  ```text
  H=640 W=640 IC=3 OC=16 stride=2 pcfg=0x07e shift=0x0a
  ```
- first CONV dispatch:
  ```text
  IN=0x00000000 WGT=0x00380000 OUT=0x0012c000
  ```
- top debug opcode alias checked through first CONV:
  ```text
  debug_opcode/debug_opcode_name match Decoder opcode
  ```
- no POOL/ADD/DMA_ST before first CONV completes
- first/last input words copied
- first/last weight words copied
- first/last DummyExec output words written

Witness:

```text
first_conv_log.md
Hardware/NPU/TestBench/first_conv_vcs.log
```

### Full Generated Backbone Outer-Control Smoke

Command:

```text
make ctrl_full_vcs
```

Result:

```text
PASS
```

Final checkpoint:

```text
pc=141 exec=36 conv=27 pool=3 add=6
dma_ld=46 dma_st=17 input_loaded=1 weight_ld=27 sram_copy=0 store=17
```

Checked:

- HALT reached
- PC parked at HALT instruction
- top debug opcode alias checked for every decoded instruction:
  ```text
  142 decoded instructions, pc=0 through pc=141
  debug_opcode/debug_opcode_name match Decoder opcode
  ```
- generated EXEC count matched
- CONV/POOL/ADD counts matched
- DMA_LD/DMA_ST counts matched
- input DRAM load observed
- weight DMA_LD count matched
- no overloaded SRAM-copy DMA_LD used
- monitor observed every DMA_ST
- concat staging DMA_ST content checked
- concat staging DMA_LD content checked
- P3/P4/P5-like final DRAM output regions received nonzero DummyExec data

Witness:

```text
log.md
Hardware/NPU/TestBench/ctrl_full_vcs_monitor.log
```

## FSDB Run

Commands:

```text
make first_conv_vcs_fsdb
make ctrl_full_vcs_fsdb
```

Results:

```text
PASS
```

Generated:

```text
Hardware/NPU/TestBench/npu_first_conv.fsdb
Hardware/NPU/TestBench/npu_ctrl_top.fsdb
```

Note:

```text
VCS/Verdi warned that very large TB arrays such as weight_bytes and dram_out_mem
were not fully dumped because of FSDB_MAX_VAR_ELEM. Control/debug RTL signals,
including debug_opcode/debug_opcode_name, are available in the FSDB.
```

## Still Not Proven

The following are intentionally not claimed by this pass:

- real convolution arithmetic correctness
- real pooling correctness
- real residual ADD correctness
- PPU/activation/quantization correctness
- PE-array/systolic scheduling correctness
- bit-exact P3/P4/P5 YOLO backbone outputs

Current sign-off level:

```text
Outer control/dataflow PASS with DummyExec.
Not a YOLO numerical correctness PASS.
```
