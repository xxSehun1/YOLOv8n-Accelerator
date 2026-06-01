# YOLOv8 Backbone RTL Status and Verification Plan

Date: 2026-05-31

This document records the current implementation status, what has been verified, what is still dummy/incomplete, and how the project should be verified if the full YOLOv8 backbone is to be completed.

The review stance here is intentionally strict: a simulation PASS with dummy compute is only evidence for outer control/data movement. It is not evidence of YOLO numerical correctness.

## Completion Update

The Level 1 and Level 2 verification gaps listed later in this plan have now been implemented and run. Detailed results are recorded in:

```text
YOLO_BACKBONE_VERIFICATION_REPORT_2026-05-31.md
decoder_opcode_log.md
dma_ctrl_unit_log.md
first_conv_log.md
log.md
```

Newly completed items:

- Decoder opcode unit test for DMA_LD, DMA_ST, CONFIG, ADDCFG, CONV, POOL, ADD, HALT, and unsupported opcodes.
- Decoder command-stability assertions for DMA and EXEC command payloads.
- Full-top debug opcode alias checks for `debug_opcode` and `debug_opcode_name`.
- Standalone DMA_ctrl unit test for DMA_LD, DMA_ST, and DRAM-staging store/load behavior.
- Re-run first-CONV and full generated-backbone outer-control smoke tests.
- Re-generated first-CONV and full-control FSDB waveforms.

## 1. Current Implementation Scope

The current design work is focused on the outer NPU control and data-exchange path:

```text
start / reset
  |
  v
ICache program fetch
  |
  v
Decoder
  |
  +-- DMA_ctrl
  |     |
  |     +-- DRAM <-> SRAM data movement
  |
  +-- DummyExec
        |
        +-- deterministic SRAM output writes
```

The active verification top is:

```text
Hardware/NPU/NPU_ctrl_top.sv
```

It is not the final compute-integrated NPU. It replaces the real compute subsystem with:

```text
Hardware/NPU/Control/DummyExec.sv
```

The current final/integration top still exists:

```text
Hardware/NPU/NPU_top.sv
```

but the current verified flow is centered on `NPU_ctrl_top`, not full real compute.

## 2. Files Added or Significantly Updated

### RTL / Control

- `Hardware/NPU/Control/DMA_ctrl.sv`
  - Updated to the newer DMA meaning:
    ```text
    DMA_LD = DRAM -> SRAM
    DMA_ST = SRAM -> DRAM
    ```
  - Old overloaded `DMA_LD SRAM->SRAM concat copy` is no longer used.

- `Hardware/NPU/NPU_ctrl_top.sv`
  - Control/dataflow integration top.
  - Instantiates:
    ```text
    ICache
    Decoder
    DMA_ctrl
    SRAM
    DummyExec
    ```
  - Adds debug outputs for waveform/TB, including:
    ```text
    debug_pc
    debug_opcode
    debug_opcode_name
    debug_exec_valid
    debug_dma_valid
    debug_*_count
    ```

- `Hardware/NPU/Control/DummyExec.sv`
  - Dummy compute engine.
  - Accepts `CONV / POOL / ADD` commands.
  - Writes deterministic data into SRAM output regions.
  - This is not real convolution/pooling/add computation.

### Testbenches

- `Hardware/NPU/TestBench/NPU_ctrl_top_tb.sv`
  - Full generated-backbone control/dataflow TB.
  - Runs until HALT.
  - Produces monitor witness and FSDB.

- `Hardware/NPU/TestBench/NPU_first_conv_tb.sv`
  - Narrow TB for only the first CONV layer.
  - Stops immediately after first CONV dummy output completes.
  - Verifies input DMA, weight DMA, CONFIG, CONV dispatch, and dummy output SRAM writes.

- `Hardware/NPU/TestBench/Makefile`
  - Added VCS targets:
    ```text
    first_conv_vcs
    first_conv_vcs_fsdb
    ctrl_full_vcs
    ctrl_full_vcs_fsdb
    ```

### Logs / Waveforms / Documentation

- `log.md`
  - Filtered full control sim monitor log.

- `first_conv_log.md`
  - Filtered first-conv monitor log.

- `Hardware/NPU/TestBench/npu_ctrl_top.fsdb`
  - Full control/dataflow FSDB.

- `Hardware/NPU/TestBench/npu_first_conv.fsdb`
  - First-conv-only FSDB.

- `Hardware/NPU/TestBench/opcode_alias.csv`
  - Opcode name mapping reference.

- `TB_CONTROL_DATAFLOW_MONITOR_2026-05-31.md`
  - Explanation of the full TB monitor strategy.

- `TB_FULL_MONITOR_WITNESS_2026-05-31.md`
  - Witness extracted from simulator monitor output.

## 3. Current ISA Contract Being Implemented

The current compiler-generated ISA uses these op groups:

```text
DMA_LD
DMA_ST
CONFIG
CONV
ADDCFG
ADD
POOL
HALT
```

Important current rule:

```text
DMA_LD always means DRAM -> SRAM.
DMA_ST always means SRAM -> DRAM.
```

Concat is no longer implemented as an overloaded SRAM-to-SRAM `DMA_LD`. The compiler now lowers concat through DRAM staging:

```text
SRAM slice
  |
  | DMA_ST
  v
DRAM scratch/output region
  |
  | DMA_LD
  v
SRAM concat destination layout
```

This is cleaner than the previous short-term ISA rule and removes the old RTL/ISS mismatch around concat copy source selection.

## 4. What Has Been Verified Completely So Far

### 4.1 First CONV Layer Control/Data Movement

Target:

```text
make first_conv_vcs
make first_conv_vcs_fsdb
```

Evidence:

```text
Hardware/NPU/TestBench/first_conv_vcs.log
Hardware/NPU/TestBench/first_conv_vcs_fsdb.log
Hardware/NPU/TestBench/npu_first_conv.fsdb
first_conv_log.md
```

Verified sequence:

```text
pc=0  DMA_LD input  DRAM 0x00000000 -> SRAM 0x00000000
pc=1  DMA_LD weight DRAM 0x01000000 -> SRAM 0x00380000
pc=2  CONFIG        H=640 W=640 IC=3 OC=16 stride=2 pcfg=0x07e shift=0x0a
pc=3  CONV          IN=0x00000000 WGT=0x00380000 OUT=0x0012c000
```

Checks performed:

- input first word copied from DRAM to SRAM
- input last word copied from DRAM to SRAM
- first weight blob first word copied from DRAM to SRAM
- first weight blob last word copied from DRAM to SRAM
- CONFIG values are decoded and consumed by first CONV
- first CONV command is issued as `exec_valid=1`, `exec_op=CONV`
- no ADD or POOL is issued before first CONV completes
- no DMA_ST occurs before first CONV completes
- DummyExec writes deterministic output to first CONV output region
- first CONV output first word matches expected dummy signature
- first CONV output last word matches expected dummy signature

Strict interpretation:

```text
This verifies first-layer control/data movement and SRAM address behavior.
It does not verify real convolution math.
```

### 4.2 Full Generated Backbone Outer Control Flow

Target:

```text
make ctrl_full_vcs
make ctrl_full_vcs_fsdb
```

Evidence:

```text
Hardware/NPU/TestBench/ctrl_full_vcs_monitor.log
Hardware/NPU/TestBench/ctrl_full_vcs_fsdb.log
Hardware/NPU/TestBench/npu_ctrl_top.fsdb
log.md
TB_FULL_MONITOR_WITNESS_2026-05-31.md
```

Verified full generated program count:

```text
pc at HALT      = 141
total EXEC      = 36
CONV            = 27
POOL            = 3
ADD             = 6
DMA_LD          = 46
DMA_ST          = 17
weight DMA_LD   = 27
SRAM-copy DMA_LD= 0
```

Key PASS checks:

```text
HALT reached
PC parked at HALT instruction
all generated EXEC ops accepted
CONV count matches generated ISA
POOL count matches generated ISA
ADD count matches generated ISA
DMA_LD count matches generated ISA
weight DMA_LD count matches generated ISA
no overloaded SRAM-copy DMA_LD was used
DMA_ST count matches generated ISA
concat staging DMA_ST content was checked
concat staging DMA_LD content was checked
P3-like final output received nonzero dummy data
P4-like final output received nonzero dummy data
P5-like final output received nonzero dummy data
```

Strict interpretation:

```text
This verifies that the outer controller can run the entire generated backbone program
to HALT with the expected operation sequence and high-level data movement.
It does not verify real PE-array computation, real pooling, real add, PPU behavior,
or numerical match with YOLOv8.
```

### 4.3 Opcode Waveform Readability

Added waveform-visible signals:

```text
debug_opcode[3:0]
debug_opcode_name[63:0]
```

Usage:

```text
Set debug_opcode_name radix to ASCII in nWave/Verdi.
```

Expected readable names:

```text
DMA_LD
DMA_ST
CONFIG
ADDCFG
CONV
ADD
POOL
HALT
```

## 5. What Is Not Verified Yet

The following are not proven by the current PASS results:

- real convolution arithmetic
- real int8 multiply-accumulate correctness
- systolic-array scheduling correctness
- line-buffer window generation correctness
- weight-buffer fill/read timing correctness
- IOMap buffer input/output ordering correctness
- ping-pong buffer hazard freedom
- opsum collection correctness
- bias handling correctness
- SiLU behavior
- maxpool numerical correctness
- ADD quantization/shift/saturation correctness
- final YOLOv8 backbone feature-map numerical match
- cycle-level performance
- bandwidth bottlenecks
- deadlock freedom under realistic compute latency
- backpressure correctness
- MMIO or CPU-writable instruction memory

Current simulation is therefore a strong bring-up check for the outer shell, but it is not a full accelerator validation.

## 6. Other Teams Must Complete These Blocks

To implement the full YOLOv8 backbone, the following teams/modules must provide real behavior and verification collateral.

### 6.1 PingPong Controller

Required responsibilities:

- consume Decoder `exec_*` command
- sequence `CONV / POOL / ADD`
- dispatch high-level operation tokens to submodules
- coordinate Weight_Buffer and IOMap_Buffer at command/transaction level
- assert `exec_done` only after real compute output is complete
- handle stride/pad/kernel/channel dimensions from CONFIG
- handle `exec_flags`, including bias and activation mode routing
- handle `exec_pconfig`, `exec_shift`, `exec_lhs_shift`, `exec_rhs_shift`

Architecture constraint:

```text
PingPong_Ctrl must not become a monolithic address-generation "God FSM".
```

The PingPong controller should issue high-level tokens such as:

```text
{op_type, in_base, weight_base, out_base, shape, stride, pad, kernel, flags}
```

Then local controllers should own detailed address generation:

```text
Weight_Buffer -> weight address sequence
IOMap_Buffer  -> fmap input/output address sequence
Line_Buffer   -> window coordinate sequence
Opsum/PPU     -> output packing/order sequence
```

Reason:

```text
Centralizing every read/write address in PingPong_Ctrl creates timing risk,
debug risk, and hidden read-before-write hazard risk.
```

Must prove:

- no buffer read-before-write hazard
- no output overwrite hazard
- correct address progression for all generated backbone layers
- correct done timing
- correct behavior for back-to-back layers
- stable valid/ready behavior under backpressure
- local submodule address generators cannot be overrun by PingPong dispatch

### 6.2 Weight Buffer Team

Required responsibilities:

- read packed weights/bias from SRAM staging area
- feed PE array in correct order
- support all generated layer weight sizes
- support double-buffering or ping-pong scheduling if expected
- publish required input/output throughput in words/cycle
- handle valid/ready backpressure without data loss or duplication

Must prove:

- first word/last word correctness
- channel/kernel ordering correctness
- weight reuse correctness
- no stale weight reuse across layers
- PE-facing stream does not starve the array under agreed benchmark assumptions
- when stalled, `valid` and `data` remain stable until accepted

### 6.3 IOMap Buffer Team

Required responsibilities:

- read input feature maps from SRAM
- write output activations back to SRAM
- provide ordered stream to line buffer / compute pipeline
- accept output stream from PPU / collector
- publish SRAM-side bandwidth demand in words/cycle
- publish compute-side stream throughput in words/cycle
- tolerate downstream stalls through a documented valid/ready protocol

Must prove:

- correct address mapping for all input/output base addresses
- correct tensor layout
- no dropped/duplicated words
- support for concat destination layouts generated by compiler
- output write path cannot overwrite unread input regions
- stream timing does not starve the compute path for fixed YOLOv8n workloads

### 6.4 Line Buffer Team

Required responsibilities:

- generate convolution windows for kernel 1 and kernel 3
- handle padding
- handle stride 1 and stride 2
- handle all generated spatial sizes:
  ```text
  640, 320, 160, 80, 40, 20
  ```
- define input/output throughput:
  ```text
  accepted input words/cycle
  produced window words/cycle
  stall behavior
  ```

Must prove:

- window coordinates match software reference
- padding values are correct
- boundary behavior is correct
- stride behavior is correct
- valid/ready stalls do not corrupt window ordering

### 6.5 PE Array / Systolic Team

Required responsibilities:

- implement int8 MAC datapath
- respect PE config
- consume ifmap/filter streams
- produce partial sums in correct order
- manage valid/ready/backpressure
- publish required ifmap/filter/ipsum bandwidth per cycle
- publish opsum production rate per cycle

Must prove:

- single PE MAC correctness
- PE array dataflow correctness
- accumulation correctness over channels/kernel positions
- correct behavior for uneven channels if present
- no X propagation in valid operation

### 6.6 OpsumCollector / PSUM Accumulation Team

Required responsibilities:

- collect partial sums from PE array
- apply bias when enabled
- manage output pixel/channel ordering
- deliver final accumulated psums to PPU

Must prove:

- correct lane ordering
- correct pixel ordering
- correct bias addition
- correct final pulse/done behavior

### 6.7 PPU / Activation / Quantization Team

Required responsibilities:

- apply right shift / requantization
- apply bias/activation controls from flags
- implement the exact approved integer SiLU/LUT/activation model
- implement maxpool if PPU owns pool behavior
- implement saturation/clamp to int8/uint8 storage format

Hard prerequisite:

```text
Do not write or accept PPU RTL until the exact integer math model is frozen.
```

The model must define:

- accumulator width
- bias width and alignment
- shift direction and shift amount semantics
- rounding mode
- saturation limits
- zero point handling
- SiLU/LUT approximation
- multiply scaling
- ADD operand alignment
- maxpool comparison domain

Must prove:

- 100% bit-exact against approved software model
- edge cases around saturation
- shift/rounding behavior
- flag combinations:
  ```text
  bias only
  bias + SiLU
  no activation
  pool
  add
  ```

### 6.8 Compiler / ISA Owner

Required responsibilities:

- keep assembler encoding stable
- keep generated ISA consistent with RTL contract
- provide layer mapping metadata
- provide golden reference tensors per layer
- define exact tensor layout in SRAM/DRAM
- define exact quantization behavior expected from RTL
- provide a bit-accurate Python or C++ golden model for the exact integer datapath
- freeze rounding, saturation, zero point, and activation/LUT behavior before PPU RTL

Must prove:

- generated instruction count and op sequence are deterministic
- memory regions do not overlap incorrectly
- concat staging addresses are legal
- final output addresses are documented
- ISS and RTL contract match
- golden tensors are generated from the same integer math contract used by RTL
- any tolerance-based result is labeled as bring-up/diagnostic only, not sign-off

## 7. Pyramid Verification Strategy

Verification must be layered from coarse to fine. Passing a high-level dummy-flow test must never be treated as proof of arithmetic correctness.

For this fixed-task accelerator, directed tests against the generated YOLOv8n workload are acceptable and pragmatic. However, dynamic simulation must be supported by protocol assertions and targeted formal checks on critical control paths. Directed tests prove the intended workload; assertions/formal checks reduce the chance of hidden timing and backpressure bugs.

### Level 0: Static / Structural Checks

Purpose:

```text
Catch obvious integration errors before simulation.
```

Benchmarks:

- lint clean for modified modules
- compile all relevant RTL
- no width truncation warnings in control paths
- no undriven critical control signals
- no multiple-driver memory/control paths

Required pass criteria:

- `NPU_ctrl_top` VCS compile clean enough for sim
- `NPU_top` compile/lint does not hide serious port mismatches
- opcode defines match compiler assembler

Strict failure examples:

- Decoder opcode mismatch
- DMA field extraction mismatch
- address truncation on SRAM address
- unconnected done/valid path

### Level 0.5: Interface Protocol and SVA Checks

Purpose:

```text
Define and enforce control-interface rules before relying on integration tests.
```

Required protocol rules:

- every valid/ready interface must define ownership of `valid`, `ready`, and `data`
- when `valid && !ready`, `valid` must remain asserted
- when `valid && !ready`, payload data must remain stable
- a transaction is accepted only on `valid && ready`
- done pulses must be one-cycle or explicitly specified
- start pulses must not be reaccepted while busy unless explicitly supported
- SRAM read/write ports must not issue illegal simultaneous accesses if the memory cannot support them

Example SVA intent:

```systemverilog
assert property (@(posedge clk) disable iff (rst)
    valid && !ready |=> valid && $stable(data));
```

Required checks:

- Decoder to DMA command stability
- Decoder to compute command stability
- PingPong to buffer command stability
- buffer stream valid/ready stability
- SRAM write address/data stability when stalled
- no read-before-write hazard on ping-pong buffers
- no overwrite of live SRAM regions

Formal target:

```text
Run formal, if available, on PingPong_Ctrl and buffer-interface wrappers.
```

Pass criteria:

- protocol assertions pass in simulation
- no assertion failure in first-conv, block-level, and full-backbone tests
- formal proves bounded hazard freedom for PingPong/buffer interfaces where practical

### Level 1: ISA Decode Unit Tests

Purpose:

```text
Verify Decoder translates each opcode into the correct control outputs.
```

Benchmarks:

- one instruction per opcode:
  ```text
  DMA_LD
  DMA_ST
  CONFIG
  ADDCFG
  CONV
  ADD
  POOL
  HALT
  unsupported opcode
  ```

Required checks:

- `debug_opcode` and `debug_opcode_name`
- `dma_valid`, `dma_is_store`
- `exec_valid`, `exec_op`
- `halted`
- PC update behavior
- CONFIG/ADDCFG latch behavior

Required pass criteria:

- every opcode produces exactly the intended control handshake
- unsupported opcode cannot deadlock

### Level 2: DMA Data Path Unit Tests

Purpose:

```text
Prove DMA_ctrl moves data in both directions correctly.
```

Benchmarks:

- small aligned `DMA_LD`, e.g. 16 words
- small aligned `DMA_ST`, e.g. 16 words
- full first input image load
- full first weight load
- DRAM staging store/load pair

Required checks:

- source first/middle/last word
- destination first/middle/last word
- `widx` reaches expected count
- `dma_done` occurs exactly once
- no write outside target region

Required pass criteria:

- byte/word address sequence is exact
- `DMA_LD` never reads SRAM as source
- `DMA_ST` never writes SRAM as destination

### Level 3: First-Layer Bring-Up Test

Current benchmark:

```text
NPU_first_conv_tb
```

Purpose:

```text
Verify the smallest meaningful sequence:
input load -> weight load -> CONFIG -> CONV dispatch -> output SRAM write.
```

Current status:

```text
PASS with DummyExec.
```

Required future upgrade:

- replace DummyExec with real compute path
- compare first layer output against golden tensor
- inspect several spatial/channel positions:
  ```text
  top-left
  top-right
  center
  bottom-left
  bottom-right
  multiple channels
  ```

Strict pass criteria:

- bring-up grade: tolerance-approved match may be used only to diagnose early datapath wiring
- sign-off grade: 100% bit-exact match with approved integer software golden
- no mismatch hidden by only checking first/last words

### Level 4: Single-Layer Real Compute Tests

Purpose:

```text
Verify individual CONV/POOL/ADD behavior before full backbone.
```

Benchmarks:

- `1x1 CONV`, stride 1
- `3x3 CONV`, stride 1, pad 1
- `3x3 CONV`, stride 2, pad 1
- residual `ADD`
- maxpool used in SPPF
- bias + SiLU layer
- no-activation layer

Required checks:

- exact output tensor comparison to golden
- shape and address correctness
- output layout correctness
- output saturation correctness

Strict pass criteria:

- every tested layer must match golden reference
- failures must report layer/op/address/channel/index
- bring-up grade may use a documented tolerance only while the integer math model is not frozen
- sign-off grade requires bit-exact INT8/INT32 outputs

### Level 5: Block-Level YOLO Backbone Tests

Purpose:

```text
Verify sequences of layers and data reuse.
```

Benchmarks:

- stem only
- first C2f/residual block
- first concat block
- downsample transition block
- SPPF block
- P3/P4/P5 output-producing segments

Required checks:

- final output of block vs software golden
- intermediate checksum per layer
- memory map consistency
- concat layout correctness

Strict pass criteria:

- each block output numerically matches golden
- all DMA staging data matches source/destination layout
- no block can pass by only checking nonzero output
- bring-up grade may use tolerance-approved comparison to localize likely datapath/ordering bugs
- sign-off grade requires every tensor element to be bit-exact unless the approved integer model itself is changed and versioned

### Level 6: Full Backbone Functional Test

Purpose:

```text
Verify full YOLOv8 backbone from input image to P3/P4/P5 outputs.
```

Benchmarks:

- one fixed deterministic synthetic input
- one real image input
- random bounded input
- all-zero input
- all-constant input
- high-contrast pattern input

Required checks:

- P3 output tensor match
- P4 output tensor match
- P5 output tensor match
- per-layer checksum trace
- final DRAM output address correctness

Strict pass criteria:

- bring-up grade: tolerance-approved comparison is allowed only as an intermediate diagnostic metric
- sign-off grade: 100% bit-exact match against the approved integer golden model
- all mismatches must be localized by layer and tensor index

Two-grade numerical policy:

```text
Bring-up grade:
  Tolerance-approved matching may be used to keep early integration moving and
  to identify gross datapath, layout, or ordering problems before the integer
  math model is frozen.

Sign-off grade:
  Tolerance is not accepted. If RTL produces 126 and golden produces 127, that
  is a failure. Either the RTL is wrong or the golden model does not match the
  frozen hardware math.
```

### Level 7: Robustness / Stress Tests

Purpose:

```text
Prove the design is not only correct on the happy path.
```

Benchmarks:

- random valid DMA sizes
- max SRAM pressure case
- repeated start/reset tests
- reset during idle
- reset during DMA
- reset during compute
- artificial DRAM latency variation
- artificial compute latency variation
- backpressure if valid/ready exists

Required checks:

- no deadlock
- no X propagation after reset recovery
- no illegal memory access
- halted behavior remains stable

Strict pass criteria:

- every timeout is a failure
- every X on control handshake after reset is a failure
- every out-of-region DRAM/SRAM access is a failure

### Level 8: Performance and Capacity Validation

Purpose:

```text
Verify the final accelerator is not merely functionally correct but viable.
```

Benchmarks:

- cycle count per layer
- DMA bandwidth per layer
- PE utilization per layer
- SRAM occupancy / peak allocation
- stall breakdown:
  ```text
  DMA wait
  weight wait
  ifmap wait
  opsum wait
  PPU wait
  ```

Required checks:

- compare against expected cycle model
- identify bottleneck per layer
- verify no pathological stalls
- measure whether SRAM/DRAM/buffer throughput can sustain the PE array
- measure starvation cycles at PE input boundaries
- measure backpressure cycles at PPU/output boundaries

Strict pass criteria:

- performance must be measured, not inferred
- every major stall source must be explainable
- if the PE array is starved, the reason must be tied to a bandwidth number, not hand-waved

## 8. Benchmark Set Recommendation

### Minimal Smoke Benchmarks

Use these for every RTL change:

```text
first_conv_vcs
ctrl_full_vcs
```

Purpose:

```text
Catch broken build, broken decode, broken DMA, broken HALT quickly.
```

### Functional Bring-Up Benchmarks

Use these after any compute-path change:

```text
single 1x1 CONV
single 3x3 stride1 CONV
single 3x3 stride2 CONV
single ADD
single POOL
first real YOLO conv layer
first residual block
first concat block
SPPF block
```

### Full Backbone Benchmarks

Use these before claiming backbone complete:

```text
synthetic deterministic image
real image
random image
all-zero image
checkerboard/high-frequency image
```

Outputs:

```text
P3-like output
P4-like output
P5-like output
```

Each benchmark must include:

- input binary
- generated ISA
- weights binary
- golden per-layer checksums
- golden final tensors
- expected output addresses
- frozen integer math spec version
- expected cycle/bandwidth budget if performance is being claimed

## 9. Verification Quality Rules

The following rules should be enforced strictly.

### Rule 1: Nonzero output is not correctness

Checking only:

```text
output != 0
```

is only a smoke check. It cannot prove data layout or math.

### Rule 2: DummyExec PASS must be labeled as dummy

Any PASS using `DummyExec` must be described as:

```text
control/dataflow PASS
```

not:

```text
YOLO backbone PASS
```

### Rule 3: Every module needs local proof before full integration

Full system failure is too hard to debug without unit evidence.

Required before full integration:

- DMA unit proof
- Decoder unit proof
- Weight buffer unit proof
- IOMap unit proof
- Line buffer unit proof
- PE array unit proof
- PPU unit proof
- ADD unit proof
- Pool unit proof

### Rule 4: Golden references must be versioned

Every numerical benchmark must record:

- compiler commit/version
- generated ISA hash
- weights hash
- input hash
- golden output hash
- quantization spec version
- rounding mode
- saturation mode
- activation/LUT model version

### Rule 4.5: Numerical checks have two grades

Numerical verification should report two different grades instead of mixing them.

Bring-up grade:

```text
Purpose:
  early integration/debug

Allowed:
  tolerance-approved comparison
  aggregate error statistics
  mismatch histograms
  top-K mismatch locations

Status label:
  BRING-UP PASS
```

Sign-off grade:

```text
Purpose:
  final correctness claim

Required:
  RTL tensor byte-for-byte equals golden tensor.

Status label:
  SIGN-OFF PASS
```

Rules:

- Tolerance-approved results must never be reported as final YOLO correctness.
- Any tolerance value must be documented with rationale, tensor type, and layer.
- Once the integer math spec is frozen, sign-off requires bit-exact output.
- If sign-off has a mismatch, the result is a failure until one of these is true:
  - RTL is fixed
  - the golden model is fixed
  - the frozen integer math spec is formally revised and versioned

### Rule 5: Waveform evidence is useful but not sufficient

FSDB helps debug and review, but final correctness must be automated by self-checking TBs.

Required:

```text
$fatal on mismatch
clear PASS/FAIL summary
machine-readable logs where possible
```

### Rule 6: Address correctness must be checked explicitly

Every memory-moving benchmark should check:

- first word
- last word
- at least one middle word
- region bounds
- no unexpected write region

### Rule 7: Backpressure and latency must not be assumed away

If later modules use valid/ready, tests must inject stalls.

The current dummy flow does not prove stall tolerance.

### Rule 8: Critical control paths require assertions

Directed simulation is necessary but insufficient for control-heavy modules.

Required assertion targets:

- Decoder command stability while waiting for `dma_done` / `exec_done`
- DMA no out-of-region access
- PingPong no read-before-write on live buffers
- PingPong no overwrite of live output buffers
- valid/ready payload stability
- one transaction accepted per handshake
- `exec_done` is not asserted before all required output writes complete

Where formal tools are available, run bounded formal on the assertion-heavy control wrappers.

### Rule 9: Throughput must be specified at boundaries

Every streaming boundary must document:

```text
producer words/cycle
consumer words/cycle
valid/ready behavior
maximum tolerated stall
FIFO depth if any
```

Without this, a numerically correct datapath may still fail as an accelerator because it cannot feed the PE array.

## 10. Current Risk Assessment

High risk:

- Real compute path is not verified.
- Real quantization/activation behavior is not frozen as a bit-exact integer model.
- Full backbone PASS currently uses dummy output, not golden tensor comparison.
- Large DRAM/SRAM memory arrays are partly omitted by FSDB default element limits.
- Existing full TB is good for control sequencing, but weak for numerical correctness.
- PingPong_Ctrl may become an unmaintainable centralized FSM if detailed address generation is not delegated.
- Dynamic simulation alone may miss backpressure and read-before-write timing bugs.

Medium risk:

- `DMA_LD/DMA_ST` semantics are now cleaner, but compiler/ISS must stay aligned.
- Concat through DRAM staging works in current generated program, but needs address-layout proof across all concat sites.
- `debug_opcode_name` is helpful for waveform, but should not be used as functional logic.
- Buffer bandwidth may be insufficient to saturate the PE array unless words/cycle targets are specified.

Low risk:

- First-level start/fetch/decode/DMA handshake is well exercised.
- HALT sequencing is exercised.
- DMA direction control is clearer than the previous overloaded DMA_LD design.

## 11. Recommended Next Steps

0. Freeze the integer math spec before real PPU/activation RTL:
   ```text
   accumulator width
   bias alignment
   rounding mode
   saturation limits
   zero point
   SiLU/LUT model
   ADD shift semantics
   maxpool comparison domain
   ```
1. Require compiler/golden team to provide a bit-exact Python or C++ model matching that integer spec.
2. Define strict valid/ready interface protocols for every submodule boundary.
3. Add SVA for command stability, valid/ready stability, and ping-pong memory hazards.
4. Add unit tests for Decoder opcode control outputs.
5. Add standalone DMA_ctrl unit TB with small deterministic transfers.
6. Ask compiler team to emit per-layer golden metadata:
   ```text
   layer id
   op type
   input/output address
   shape
   checksum
   final tensor binary
   integer math spec version
   ```
7. Replace DummyExec one block at a time:
   ```text
   DummyExec -> real ADD only
   DummyExec -> real POOL only
   DummyExec -> real first CONV only
   ```
8. Build first real CONV bit-exact golden comparison.
9. Build first residual ADD bit-exact golden comparison.
10. Build first concat block bit-exact golden comparison.
11. Only after those pass, attempt full real backbone.

## 12. Bottom Line

Current state:

```text
Outer control/dataflow path is implemented and meaningfully verified.
First CONV control/data movement is verified.
Full generated backbone control sequence reaches HALT with expected op counts.
```

Not yet true:

```text
The actual YOLOv8 backbone computation is not verified.
The actual systolic/PPU/pooling/add datapath is not proven.
The final P3/P4/P5 tensors are not numerically validated.
```

The next major milestone should be:

```text
First real CONV layer 100% bit-exact match against the frozen integer golden output.
```

After that, move up the pyramid one level at a time.
