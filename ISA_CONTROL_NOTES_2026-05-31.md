# ISA / Control Notes

Date: 2026-05-31

## Purpose

This document records the current ISA interpretation used by the control/dataflow simulation target in this repo.

Scope:

- Current generated YOLOv8 backbone ISA.
- How the outer NPU control RTL interprets each instruction.
- Which part of the YOLO backbone each instruction supports.
- Current ISA problems that should be addressed by the next ISA revision.

Current control target:

```text
TB start pulse
  |
  v
NPU_ctrl_top
  |
  +-- ICache
  +-- Decoder
  +-- DMA_ctrl
  +-- SRAM
  +-- DummyExec
```

This target verifies ISA/control/data movement. It does not verify numerical YOLO correctness.

## Current ISA Set

Instructions are 128-bit fixed length.

Opcode field:

```text
instr[127:124]
```

Current opcode set:

```text
0x1 CONV
0x2 POOL
0x3 CONCAT
0x4 ADD
0x5 OTHER
0x6 CONFIG
0x7 BIAS
0x8 DMA_LD
0x9 DMA_ST
0xA ADDCFG
0xF HALT
```

Currently generated backbone uses:

```text
DMA_LD
CONFIG
CONV
ADDCFG
ADD
POOL
DMA_ST
HALT
```

Currently generated backbone does not use:

```text
CONCAT
OTHER
BIAS
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

## Instruction Interpretation

### CONFIG

Current interpretation:

```text
CONFIG is a state-latching instruction.
It does not launch compute.
It configures the next CONV / POOL / ADD.
```

Fields:

```text
IN_H
IN_W
IN_C
OUT_C
STRIDE
PE_CONFIG
SHIFT
```

YOLO backbone role:

```text
Layer shape / mapping / quant setup before compute.
```

Typical sequence:

```text
CONFIG
CONV
```

or:

```text
CONFIG
POOL
```

or:

```text
CONFIG
ADD
```

### ADDCFG

Current interpretation:

```text
ADDCFG is a state-latching instruction.
It configures the next ADD.
```

Fields:

```text
LHS_SHIFT
RHS_SHIFT
```

YOLO backbone role:

```text
Residual shortcut add requantization setup.
```

Typical sequence:

```text
ADDCFG
CONFIG
ADD
```

### CONV

Current interpretation:

```text
CONV launches a compute operation.
Decoder asserts exec_valid.
Compute engine returns exec_done.
```

Fields:

```text
IN      input feature-map SRAM address
WGT     weight/bias SRAM address
OUT     output feature-map SRAM address
FLAGS   activation / bias flags
STRIDE
PAD
KERNEL
```

Common flags:

```text
FLAGS = 0xB
bit0 sigmoid
bit1 multiply
bit3 bias
=> bias + SiLU
```

YOLO backbone role:

```text
Conv module
C2f internal conv
Downsample conv
SPPF surrounding conv
1x1 conv
3x3 conv
```

Current simulation behavior:

```text
DummyExec writes deterministic dummy output to OUT and returns exec_done.
No real convolution is performed in the control simulation target.
```

### ADD

Current interpretation:

```text
ADD launches a compute operation.
Decoder asserts exec_valid.
Compute engine returns exec_done.
```

Fields use the EXEC format:

```text
IN   lhs SRAM address
WGT  rhs SRAM address
OUT  output SRAM address
```

YOLO backbone role:

```text
C2f / bottleneck residual shortcut add.
```

Current simulation behavior:

```text
DummyExec writes deterministic dummy output to OUT and returns exec_done.
No real residual add is performed in the control simulation target.
```

### POOL

Current interpretation:

```text
POOL launches a compute operation.
Decoder asserts exec_valid.
Compute engine returns exec_done.
```

Fields:

```text
IN
OUT
STRIDE
PAD
KERNEL
```

YOLO backbone role:

```text
SPPF maxpool.
```

Current generated program uses three POOL instructions for SPPF.

Current simulation behavior:

```text
DummyExec writes deterministic dummy output to OUT and returns exec_done.
No real maxpool is performed in the control simulation target.
```

### DMA_LD

Current interpretation:

```text
DMA_LD moves data into SRAM.
```

However, the current compiler overloads `DMA_LD` with multiple meanings.

Current decode rule:

```text
if dma_dram >= 0x0100_0000:
    weight load: DRAM[dma_dram] -> SRAM[dma_sram]

else if input image has not been loaded:
    input load: DRAM[dma_dram] -> SRAM[dma_sram]
    input_loaded = 1

else:
    concat copy: SRAM[dma_dram] -> SRAM[dma_sram]
```

YOLO backbone role:

```text
Input image preload
Conv weight/bias preload
C2f / SPPF concat copy
```

Important implementation detail:

```systemverilog
sram_wdata = tr_src_sram ? sram_rdata : dram_rdata;
```

This means:

```text
DRAM -> SRAM uses dram_rdata
SRAM -> SRAM uses sram_rdata
```

The TB checks at least one concat-copy data value exactly:

```text
source SRAM word == destination SRAM word
```

### DMA_ST

Current interpretation:

```text
SRAM[dma_sram] -> DRAM[dma_dram]
```

YOLO backbone role:

```text
Spill backbone outputs to DRAM for the neck.
```

Generated output regions:

```text
P3-like: DRAM 0x00200000, size 0x00064000
P4-like: DRAM 0x00264000, size 0x00032000
P5-like: DRAM 0x00296000, size 0x00019000
```

### HALT

Current interpretation:

```text
HALT stops instruction execution.
halted = 1
```

YOLO backbone role:

```text
Backbone program finished.
```

### CONCAT

Current status:

```text
Opcode exists.
Generated backbone does not emit OP_CONCAT.
RTL control simulation does not depend on OP_CONCAT.
```

Actual concat behavior is implemented through overloaded `DMA_LD` SRAM-to-SRAM copies.

### OTHER

Current status:

```text
Opcode exists.
Generated backbone does not emit OP_OTHER.
Not implemented as a real CPU fallback path in the current control target.
```

Possible intended role:

```text
Unsupported op / CPU fallback trap.
```

### BIAS

Current status:

```text
Opcode exists.
Generated backbone does not emit OP_BIAS.
```

Bias is currently represented by:

```text
CONV FLAGS bit3
```

The bias data is packed into the weight blob.

Expected convention:

```text
bias address = WGT + OUT_C * IN_C * KERNEL * KERNEL
```

## Current Backbone Instruction Patterns

### ConvModule

```text
DMA_LD   weight/bias blob DRAM -> SRAM
CONFIG   tensor shape + PE_CONFIG + quant shift
CONV     input SRAM + weight SRAM -> output SRAM
```

### Residual Shortcut

```text
ADDCFG   lhs/rhs requant shift
CONFIG   tensor shape
ADD      lhs SRAM + rhs SRAM -> output SRAM
```

### SPPF Maxpool

```text
CONFIG
POOL
```

### Concat

Current generated form:

```text
DMA_LD source SRAM -> destination SRAM
DMA_LD source SRAM -> destination SRAM
...
next CONV reads concat base address
```

Example:

```text
DMA_LD DRAM:0x000C8000 SRAM:0x00190000 SIZE:0x00064000
DMA_LD DRAM:0x0012C000 SRAM:0x001F4000 SIZE:0x00064000
DMA_LD DRAM:0x00000000 SRAM:0x00258000 SIZE:0x00064000
CONFIG IN_C:48
CONV IN:0x00190000
```

Although the field name is `DRAM`, in this concat case it carries the source SRAM address.

### Backbone Output Spill

```text
DMA_ST SRAM -> DRAM
```

### Program End

```text
HALT
```

## Current ISA Problems

### 1. DMA_LD Has Overloaded Meaning

`DMA_LD` currently means both:

```text
DRAM -> SRAM
SRAM -> SRAM
```

This forces RTL to use a heuristic.

Current heuristic:

```text
first low-address DMA_LD = input image DRAM load
later low-address DMA_LD = concat SRAM copy
high-address DMA_LD      = weight DRAM load
```

Reason this is necessary:

```text
DRAM_INPUT_BASE = 0x00000000
SRAM_ACT_BASE   = 0x00000000
```

The address spaces overlap, so address range alone cannot distinguish input DRAM from activation SRAM.

Recommendation for next ISA:

```text
DMA_LD    DRAM -> SRAM
DMA_ST    SRAM -> DRAM
DMA_COPY  SRAM -> SRAM
```

or formally define and use:

```text
OP_CONCAT
```

### 2. CONCAT Opcode Exists But Is Not Used

The ISA defines `OP_CONCAT`, but the compiler emits multiple overloaded `DMA_LD` copies instead.

Problem:

```text
The ISA spec suggests CONCAT exists.
The generated program does not use it.
RTL must match the compiler, not the unused opcode.
```

Recommendation:

```text
Either remove/ignore OP_CONCAT and add DMA_COPY,
or define OP_CONCAT fields and make the compiler emit OP_CONCAT.
```

For current hardware flow, `DMA_COPY` is cleaner because the compiler already lays out concat destinations.

### 3. CONFIG Is Hidden State

`CONV`, `POOL`, and `ADD` depend on the most recent `CONFIG`.

Problem:

```text
If CONFIG is missing, stale config may be used.
If instructions are reordered, behavior can silently break.
```

Recommendation:

```text
Add config_valid checks in Decoder,
or move required shape fields into each compute instruction.
```

### 4. ADDCFG Is Hidden State

`ADD` depends on the most recent `ADDCFG`.

Problem:

```text
If ADDCFG is missing, stale shifts may be used.
```

Recommendation:

```text
Add addcfg_valid checks,
or move lhs/rhs shift fields into ADD.
```

### 5. CONV FLAGS Mix Bias And Activation Semantics

Current flags combine:

```text
bias present
sigmoid
multiply
relu
```

Problem:

```text
Bias storage convention is implicit.
Activation implementation requirements are implicit.
```

Recommendation:

Define explicitly:

```text
if FLAG_BIAS:
    bias starts at WGT + OUT_C * IN_C * KERNEL * KERNEL

if FLAG_SIGMOID and FLAG_MULTIPLY:
    operation is quantized SiLU
```

### 6. OTHER / BIAS Opcodes Are Undefined In Current Flow

Current generated backbone does not use `OTHER` or `BIAS`.

Problem:

```text
If these appear, current control flow does not define a robust behavior.
```

Recommendation:

```text
Specify whether unsupported opcodes produce error, CPU fallback, or no-op.
```

### 7. HALT Has No Error/Fallback Status

Current status:

```text
HALT -> halted = 1
```

Problem:

```text
No distinction between normal done, illegal opcode, CPU fallback request, or runtime error.
```

Recommendation for future wrapper:

```text
done
busy
error
illegal_opcode
request_cpu
pc
```

## Current Control-Flow Assumptions

The current implementation assumes:

```text
1. Compiler is unchanged.
2. Generated ISA is unchanged.
3. ICache uses $readmemh.
4. TB pulses start.
5. Decoder executes one instruction at a time.
6. DMA and EXEC are blocking.
7. CONFIG and ADDCFG are latched state.
8. DMA_LD overload follows Compiler/npu_iss.py.
9. Internal compute can be dummied.
10. Pass criteria is full instruction stream reaches HALT.
```

Current pass status:

```text
ISA/control/dataflow integration: PASS
real YOLO numeric correctness: NOT YET
```

## Files Most Likely To Change For A New ISA

When a new ISA is provided, likely update points are:

```text
Hardware/NPU/define.svh
Hardware/NPU/Control/Decoder.sv
Hardware/NPU/Control/DMA_ctrl.sv
Hardware/NPU/NPU_ctrl_top.sv
Hardware/NPU/TestBench/NPU_ctrl_top_tb.sv
Hardware/NPU/TestBench/Makefile
```

The target external flow should remain:

```text
start
  -> fetch
  -> decode
  -> dispatch DMA or EXEC
  -> wait done
  -> next PC
  -> HALT
```
