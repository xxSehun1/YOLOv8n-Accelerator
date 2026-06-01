# PLAN2: Full YOLOv8n Backbone RTL Completion And Bit-Exact Verification

Date: 2026-05-31

## Goal

從目前已經 PASS 的 outer control/dataflow 基礎出發，完成完整 YOLOv8n backbone RTL：

```text
ICache
  -> Decoder
  -> DMA_ctrl
  -> real compute subsystem
  -> SRAM / DRAM
  -> HALT
```

最終要求：

```text
RTL final P3/P4/P5 backbone outputs must match software golden exactly.
No tolerance is accepted for final sign-off.
```

目前已完成的部分是：

```text
Outer control/dataflow PASS with DummyExec.
Decoder opcode unit test PASS.
DMA_ctrl unit test PASS.
First-CONV control/dataflow smoke PASS.
Full generated ISA reaches HALT with expected op counts.
```

PLAN2 的工作是把 `DummyExec` 換成真實 compute path，並建立階段性驗證，直到完整 backbone bit-exact PASS。

## Compiler / RTL Responsibility Boundary

RTL 不負責重新理解 YOLO graph，也不負責推導 BatchNorm、Split、Concat 等高階 graph semantic。這些工作必須由 compiler / software stack 在 lowering 階段完成。

Compiler side responsibilities:

```text
BatchNorm folding into CONV weights/bias
Split lowering into explicit SRAM/DRAM address ranges
Concat lowering into legal DMA_ST/DMA_LD staging or a future explicit CONCAT ISA
activation flag generation
shape / stride / pad / kernel encoding
weight and bias packing
SRAM/DRAM memory layout
per-layer golden tensor generation
```

RTL side responsibility:

```text
Strictly execute the generated ISA.
Do not infer missing graph operations.
Do not reinterpret memory layout beyond the ISA and frozen memory-map spec.
For each emitted CONV / POOL / ADD / DMA instruction, produce exactly the software-defined result.
```

This means a missing `Split` or `BatchNorm` opcode is not an RTL bug by itself. It is valid only if the compiler has already represented that graph behavior through weights, bias, address mapping, and emitted ISA.

## Non-Negotiable Correctness Policy

### Final Sign-Off Rule

最終驗證只接受：

```text
RTL tensor byte-for-byte equals software golden tensor.
```

也就是：

```text
P3 RTL == P3 golden
P4 RTL == P4 golden
P5 RTL == P5 golden
```

如果 RTL 和 golden 只差 1 LSB，也算 FAIL。除非正式修正並版本化軟體 golden 或 integer math spec。

### Bring-Up Rule

開發中可以使用 checksum、局部 sample、mismatch histogram 幫助 debug，但只能標成：

```text
BRING-UP diagnostic
```

不能標成 final PASS。

## Phase 0: Freeze Software Golden Contract

這一階段必須先完成，否則後面的 RTL 無法判定對錯。

### Required Inputs

Compiler / software side must provide:

```text
generated npu_program.hex
full_instructions.txt
weights.bin
input tensor binary
per-layer metadata
per-layer golden output tensor
final P3/P4/P5 golden output tensors
bit-exact integer reference model
```

每一份 artifact 都要記錄 hash：

```text
compiler commit
ISA file hash
weights hash
input hash
golden output hash
integer math spec version
```

### Integer Math Spec Must Define

必須凍結以下項目：

```text
input activation format
weight format
bias format
accumulator width
zero point
scale / shift meaning
rounding mode
saturation limit
signed / unsigned interpretation
SiLU approximation or LUT
SiLU multiply behavior
ADD lhs/rhs shift behavior
POOL comparison domain
output packing order
tensor memory layout
```

### Pass Criteria

Phase 0 PASS 條件：

```text
Software ISS can run the generated ISA.
Software ISS produces per-layer and final golden tensors.
Every golden file is versioned and hash-recorded.
RTL team can reproduce the same golden from repo files.
```

如果 Phase 0 沒有完成，不能開始宣稱 RTL numerical correctness。

## Phase 1: Define Hardware Compute Boundary

目前 `NPU_ctrl_top` 的 compute side 是 `DummyExec`：

```text
Decoder exec_* -> DummyExec -> SRAM port B
```

PLAN2 要替換成：

```text
Decoder exec_* -> ComputeTop -> SRAM port B -> done
```

### Proposed ComputeTop Interface

ComputeTop 對 Decoder 保持目前 command interface：

```systemverilog
input  logic        exec_valid;
input  logic [1:0]  exec_op;       // CONV=0, POOL=1, ADD=2
input  logic [15:0] exec_in_h;
input  logic [15:0] exec_in_w;
input  logic [15:0] exec_in_c;
input  logic [15:0] exec_out_c;
input  logic [31:0] exec_in_addr;
input  logic [31:0] exec_wgt_addr;
input  logic [31:0] exec_out_addr;
input  logic [11:0] exec_flags;
input  logic [3:0]  exec_stride;
input  logic [3:0]  exec_pad;
input  logic [3:0]  exec_kernel;
input  logic [9:0]  exec_pconfig;
input  logic [5:0]  exec_shift;
input  logic [5:0]  exec_lhs_shift;
input  logic [5:0]  exec_rhs_shift;
output logic        exec_done;
```

ComputeTop 對 SRAM 初期先維持單一 read/write port， correctness-first：

```systemverilog
output logic        sram_en;
output logic        sram_we;
output logic [21:0] sram_addr;
output logic [31:0] sram_wdata;
input  logic [31:0] sram_rdata;
```

### Correctness-First Debug Milestone

第一版 functional compute 可以不追求效能，不先做 full systolic optimization。它只能作為 debug / reference milestone，用來驗證 integer math、tensor layout、ISA sequencing：

```text
one command at a time
simple FSM
deterministic SRAM access order
software-like nested loops
bit-exact integer math
```

理由：

```text
如果直接接高效 systolic + buffer + PPU，debug 空間太大。
先做 correctness reference RTL，讓 per-op / per-layer golden mismatch 可以快速定位。
之後再逐步替換成高效 PE-array implementation。
```

Hard limitation:

```text
This sequential correctness-first ComputeTop is not an accelerator.
It is not acceptable for final project sign-off.
It cannot be used to claim full-backbone completion.
```

Any PASS produced by this model must be labeled:

```text
BRING-UP / DEBUG-REFERENCE PASS
```

not:

```text
FINAL BACKBONE PASS
```

## Phase 2: Implement Bit-Exact Primitive Compute Blocks

先做小而可驗證的 arithmetic primitive，不直接寫大 FSM。

### Mandatory Datapath-Width Rule

All arithmetic modules must explicitly define internal signedness, width, overflow behavior, and saturation behavior. Do not rely on implicit Verilog truncation, implicit sign extension, or tool-dependent cast behavior.

Minimum explicit requirements:

```text
activation input byte domain: uint8 with zero point 128
signed activation domain: int9 or wider after subtracting zero point
weight domain: int8
bias domain: int32
MAC product domain: signed product with explicit extension before accumulation
accumulator domain: at least int32, widened if software model requires it
requant shift: explicit arithmetic right shift
rounding: exactly software-defined; currently no hidden rounding may be inferred
saturation: explicit clamp before output packing
packed output domain: uint8
ADD internal domain: explicit signed widened add before saturation
POOL compare domain: explicit signed activation domain
```

Every RTL file implementing arithmetic must contain localparams or comments identifying the chosen widths, and every narrowing conversion must be through a named clamp/pack path.

### Required Primitive Modules

```text
QuantizeUnit
ActivationUnit
ConvMacUnit
PoolCompareUnit
AddUnit
TensorAddrGen
TensorPackUnpack
```

### QuantizeUnit

Responsibilities:

```text
apply shift
round exactly as software
apply zero point if required
saturate exactly as software
pack output byte exactly as software
explicitly document accumulator/input/output widths
avoid implicit truncation
```

Unit tests:

```text
positive accumulator
negative accumulator
zero
max saturation
min saturation
rounding boundary
all supported shift values
```

PASS:

```text
Every tested scalar equals software golden exactly.
```

### ActivationUnit

Responsibilities:

```text
support no activation
support bias only path
support SiLU path used by FLAGS=0x00b
support any current compiler-emitted flag combination
```

Unit tests:

```text
small scalar sweep
edge saturation sweep
SiLU LUT or approximation table comparison
flag combination comparison
```

PASS:

```text
Activation output equals software model exactly.
```

### AddUnit

Responsibilities:

```text
read lhs tensor
read rhs tensor
apply lhs/rhs shifts from ADDCFG
add in exact integer domain
quantize / saturate exactly
write output tensor
use explicit signed widened datapath before clamp
avoid implicit truncation on output pack
```

Unit tests:

```text
small 1x1x4 tensor
multi-channel tensor
lhs_shift != rhs_shift
same input/output alias case if generated ISA uses it
saturation cases
```

PASS:

```text
Every ADD output byte equals software golden.
```

### PoolCompareUnit

Responsibilities:

```text
support generated maxpool kernel=5 stride=1 pad=2
use exact comparison domain
handle padding exactly
preserve output layout
```

Unit tests:

```text
single-channel 5x5
multi-channel tensor
border/top-left
border/top-right
center
all-equal values
negative/signed interpretation if applicable
```

PASS:

```text
Every POOL output byte equals software golden.
```

### ConvMacUnit

Responsibilities:

```text
support 1x1 and 3x3
support stride 1 and stride 2
support pad 0 and pad 1
support bias flag
support SiLU flag path
support generated in/out channel counts
read packed activations and weights from SRAM
write packed output activation to SRAM
```

Unit tests:

```text
1x1 CONV, tiny shape
3x3 CONV stride 1 pad 1, tiny shape
3x3 CONV stride 2 pad 1, tiny shape
first real YOLO conv
bias-only
bias + SiLU
no activation
saturation and rounding edge cases
```

PASS:

```text
Every CONV output byte equals software golden.
```

## Phase 3: Implement Functional ComputeTop

ComputeTop owns high-level command execution:

```text
if exec_op == CONV: run ConvEngine
if exec_op == POOL: run PoolEngine
if exec_op == ADD : run AddEngine
```

### ComputeTop Internal FSM

Recommended first version:

```text
S_IDLE
S_LATCH_CMD
S_RUN_CONV / S_RUN_POOL / S_RUN_ADD
S_DONE
```

Rules:

```text
Latch exec_* fields once when command starts.
Hold busy until operation completes.
Pulse exec_done once.
Do not accept a new command before returning to IDLE.
Do not write outside declared output tensor region.
```

### SRAM Access Strategy

Correctness-first implementation:

```text
single SRAM port for compute
sequential reads
local registers for current input/weight/bias words
sequential output writes
no overlap with DMA because Decoder already serializes DMA and EXEC
```

This is slow but simple and deterministic.

### Pass Criteria

ComputeTop unit TB must pass:

```text
single CONV command
single POOL command
single ADD command
back-to-back command sequence
exec_done one pulse per command
no illegal SRAM access
output tensor exactly equals software golden
```

## Phase 4: Replace DummyExec In NPU_ctrl_top

Create a new integration option:

```text
NPU_ctrl_top_real_compute
```

or parameterize existing top:

```text
USE_DUMMY_EXEC = 0
```

Recommended:

```text
Keep current DummyExec tests alive.
Add a new real-compute top so control bring-up regression stays fast.
```

### Integration Requirements

```text
Decoder command payload unchanged.
DMA_ctrl unchanged unless memory bandwidth issue is discovered.
ICache unchanged.
TB DRAM model unchanged.
SRAM storage layout unchanged.
```

### Pass Criteria

First integration smoke:

```text
input DMA_LD
weight DMA_LD
CONFIG
real CONV
compare first CONV output to golden
```

No full-backbone attempt until first CONV bit-exact PASS.

## Phase 5: Layer-Level Verification Ladder

Move one step at a time. Each level must pass before moving upward.

### Level 5.1: First Real CONV

Run:

```text
pc=0 DMA_LD input
pc=1 DMA_LD first weight
pc=2 CONFIG
pc=3 CONV
stop after first CONV
```

Checks:

```text
all output bytes match first-conv golden tensor
report first mismatch index/address/channel
check first/middle/last words
check top-left/top-right/center/bottom-left/bottom-right
check multiple channels
```

PASS:

```text
100% bit-exact first CONV tensor.
```

### Level 5.2: Single Operation Regression

Run separately:

```text
single 1x1 CONV
single 3x3 stride1 CONV
single 3x3 stride2 CONV
single ADD
single POOL
```

PASS:

```text
Every output tensor is bit-exact.
```

### Level 5.3: First Residual Block

Run until first ADD completes:

```text
CONV sequence
ADDCFG
CONFIG
ADD
```

PASS:

```text
ADD output tensor equals software golden.
```

### Level 5.4: First Concat/Staging Block

Run through the first generated concat-equivalent region:

```text
DMA_ST staging
DMA_LD reload
next CONV reads concat destination base
```

Checks:

```text
staged DRAM bytes equal source SRAM bytes
reloaded SRAM bytes equal staged DRAM bytes
next CONV input layout equals software concat layout
next CONV output equals golden
```

PASS:

```text
Concat layout and following CONV output are bit-exact.
```

### Level 5.5: SPPF Block

Run through:

```text
CONV
POOL
POOL
POOL
concat staging
final SPPF CONV
```

PASS:

```text
SPPF block output equals golden.
```

## Phase 6: Full Backbone Verification

Only start after Phase 5 PASS.

Important distinction:

```text
Phase 6 may be run first on the correctness-first debug ComputeTop to localize numerical issues.
That result is useful, but it is not final project sign-off.
Final sign-off is defined in Phase 6.5 and requires the real parallel systolic datapath.
```

### Full Backbone Test Inputs

Required:

```text
deterministic synthetic input
all-zero input
all-constant input
checkerboard/high-frequency input
one real image input
```

For each input, software side must provide:

```text
input binary
weights binary
generated ISA
per-layer checksums
final P3/P4/P5 golden tensors
```

### Full Backbone Checks

TB must check:

```text
HALT reached
PC parked at HALT
op counts match generated ISA
all DMA transfers legal
all real compute commands completed
per-layer output checksum matches
P3 tensor byte-exact
P4 tensor byte-exact
P5 tensor byte-exact
```

Mismatch report must include:

```text
output name: P3/P4/P5
byte index
tensor coordinate if metadata available
DRAM address
RTL value
golden value
previous layer id
producer opcode pc
```

### Final PASS

Debug-reference full-backbone PASS requires:

```text
All required inputs pass.
All P3/P4/P5 tensors are byte-exact.
No assertion failures.
No illegal SRAM/DRAM access.
No timeout.
Result is labeled DEBUG-REFERENCE PASS if it uses the sequential ComputeTop.
```

## Phase 6.5: Real Systolic / PE-Array Sign-Off

The final full-backbone verification must be executed on the real accelerator datapath:

```text
Decoder
  -> PingPong_Ctrl
  -> Weight_Buffer
  -> IOMap_Buffer
  -> Line_Buffer
  -> PE_array / systolic datapath
  -> OpsumCollector / PSUM accumulation
  -> PPU / Quantize / Activation / Pool / ADD path
  -> SRAM / DRAM
```

This phase replaces the sequential debug ComputeTop with the real parallel hardware architecture.

### Required Real-Hardware Integration

The sign-off top must instantiate or connect the actual project datapath:

```text
PingPong_Ctrl.sv
Weight_Buffer.sv
IOMap_Buffer.sv
Line_Buffer.sv
PE_array.sv
OpsumCollector.sv
PPU.sv
```

Sequential software-like loops may remain in the repo only as:

```text
reference RTL
debug accelerator model
unit-test oracle helper
```

They cannot be the final backbone engine.

### Additional Real-Hardware Checks

In addition to byte-exact output comparison, real-hardware sign-off must verify:

```text
PE-array command acceptance
weight-buffer fill and drain ordering
IOMap read/write address ordering
line-buffer window ordering
opsum accumulation ordering
PPU quantization/activation ordering
valid/ready backpressure stability
no read-before-write hazard
no overwrite of live feature maps
no dropped or duplicated stream word
real exec_done only after final output write
```

### Real-Hardware Final PASS

Final project PASS requires:

```text
The real parallel systolic/PE-array datapath runs the full generated backbone ISA.
All required inputs pass.
All P3/P4/P5 tensors are byte-exact against software golden.
No assertion failures.
No illegal SRAM/DRAM access.
No timeout.
No hidden fallback to sequential debug ComputeTop.
```

## Phase 7: Assertions And Protocol Verification

Keep existing Decoder assertions and add more.

### Required Assertions

Decoder:

```text
DMA command stable until dma_done
EXEC command stable until exec_done
HALT remains halted
unsupported opcode cannot deadlock
```

DMA_ctrl:

```text
DMA_LD never writes DRAM
DMA_ST never writes SRAM
address increments by 4 bytes
dma_done is one completion event per command
no access outside allowed DRAM/SRAM regions
```

ComputeTop:

```text
exec_done only after final output write
command payload latched at start
no output write outside tensor output range
no read outside input/weight tensor range
no X on SRAM address/write enable/data during active transfer
```

Operation engines:

```text
CONV loop counters stay in legal range
POOL window coordinates stay legal or pad path selected
ADD read addresses stay in legal tensor ranges
quantize output never X
```

Real systolic datapath:

```text
PingPong command payload stable until accepted
Weight_Buffer stream payload stable under stall
IOMap stream payload stable under stall
Line_Buffer output window stable under stall
PE_array input valid/data stable under stall
OpsumCollector output valid/data stable under stall
PPU output valid/data stable under stall
no read-before-write on ping-pong/live buffers
no overwrite of live output regions
```

## Phase 8: File And Target Plan

### New RTL Files

Proposed:

```text
Hardware/NPU/Compute/ComputeTop.sv
Hardware/NPU/Compute/ConvEngine.sv
Hardware/NPU/Compute/PoolEngine.sv
Hardware/NPU/Compute/AddEngine.sv
Hardware/NPU/Compute/QuantizeUnit.sv
Hardware/NPU/Compute/ActivationUnit.sv
Hardware/NPU/Compute/TensorAddrGen.sv
Hardware/NPU/Compute/TensorPack.sv
```

### New TB Files

Proposed:

```text
Hardware/NPU/TestBench/QuantizeUnit_tb.sv
Hardware/NPU/TestBench/ActivationUnit_tb.sv
Hardware/NPU/TestBench/AddEngine_tb.sv
Hardware/NPU/TestBench/PoolEngine_tb.sv
Hardware/NPU/TestBench/ConvEngine_tb.sv
Hardware/NPU/TestBench/ComputeTop_tb.sv
Hardware/NPU/TestBench/NPU_first_real_conv_tb.sv
Hardware/NPU/TestBench/NPU_full_backbone_real_tb.sv
```

### New Make Targets

Proposed:

```text
quantize_unit_vcs
activation_unit_vcs
add_engine_vcs
pool_engine_vcs
conv_engine_vcs
compute_top_vcs
first_real_conv_vcs
first_real_conv_vcs_fsdb
full_backbone_real_vcs
full_backbone_real_vcs_fsdb
```

## Phase 9: Review Gates

Do not merge a phase unless its gate passes.

### Gate A: Golden Contract

```text
integer math spec frozen
golden files generated
hashes recorded
software ISS deterministic
```

### Gate B: Primitive Units

```text
QuantizeUnit PASS
ActivationUnit PASS
AddUnit scalar/tiny tensor PASS
Pool tiny tensor PASS
Conv tiny tensor PASS
```

### Gate C: First Real CONV

```text
first YOLO conv output bit-exact
failure report is useful if mismatch occurs
FSDB generated
```

### Gate D: Block-Level

```text
first residual block bit-exact
first concat/staging block bit-exact
SPPF block bit-exact
```

### Gate E: Full Backbone

Debug-reference gate:

```text
full backbone bit-exact on sequential/debug ComputeTop
result clearly marked DEBUG-REFERENCE PASS
not accepted as final project completion
```

### Gate F: Real Hardware Sign-Off

```text
full backbone bit-exact on real parallel systolic/PE-array datapath
P3/P4/P5 exact for all required inputs
no assertion failures
no sequential debug fallback
```

## Practical Implementation Order

Recommended order:

```text
1. Freeze and import software golden files.
2. Build Python/C helper to convert golden tensors into hex/mem files for TB.
3. Implement QuantizeUnit and its TB.
4. Implement ActivationUnit and its TB.
5. Implement AddEngine and its TB.
6. Implement PoolEngine and its TB.
7. Implement ConvEngine with tiny-shape TB.
8. Run first real YOLO CONV bit-exact TB.
9. Integrate ComputeTop into a real-compute NPU top.
10. Run first residual block.
11. Run first concat/staging block.
12. Run SPPF block.
13. Run full backbone on deterministic input.
14. Mark sequential full-backbone result as DEBUG-REFERENCE only.
15. Integrate real PingPong / Buffer / Line_Buffer / PE_array / OpsumCollector / PPU datapath.
16. Run real-hardware first CONV, residual, concat/staging, and SPPF block tests.
17. Run real-hardware full backbone on deterministic input.
18. Add zero/constant/checkerboard/real-image regressions on real hardware.
19. Regenerate final logs and FSDB from the real-hardware passing RTL.
```

## Risk List

High risk:

```text
software golden integer math not frozen
SiLU approximation mismatch
rounding/saturation mismatch
packed tensor layout mismatch
weight/bias layout mismatch
in-place SRAM overwrite hazard
full simulation runtime too long with correctness-first engine
```

Mitigation:

```text
lock software spec first
test primitive math before engines
compare per-layer before full backbone
report exact mismatch coordinate/address
keep DummyExec regression alive
optimize only after bit-exact functional RTL exists
```

## Definition Of Done

PLAN2 is complete only when:

```text
DummyExec is no longer used for real-backbone sign-off.
Every generated CONV / POOL / ADD has real RTL behavior.
Full generated ISA runs to HALT.
P3/P4/P5 RTL outputs match software golden byte-for-byte on the real parallel systolic/PE-array datapath.
All unit, layer, block, and full-backbone tests pass.
All logs and FSDB are regenerated from the passing RTL.
Remaining limitations are documented clearly.
Sequential correctness-first ComputeTop, if present, is labeled debug/reference only and is not used for final sign-off.
```
