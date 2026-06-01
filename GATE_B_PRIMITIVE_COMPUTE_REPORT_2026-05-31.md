# Gate B Primitive Compute Report

Date: 2026-05-31

## Scope

This phase implements and verifies the foundational bit-exact compute primitives required before replacing `DummyExec`.

Implemented RTL:

- `Hardware/NPU/Compute/QuantizeUnit.sv`
- `Hardware/NPU/Compute/ActivationUnit.sv`
- `Hardware/NPU/Compute/AddUnit.sv`
- `Hardware/NPU/Compute/PoolCompareUnit.sv`
- `Hardware/NPU/Compute/ConvMacUnit.sv`

Implemented VCS unit testbenches:

- `Hardware/NPU/TestBench/QuantizeUnit_tb.sv`
- `Hardware/NPU/TestBench/ActivationUnit_tb.sv`
- `Hardware/NPU/TestBench/AddUnit_tb.sv`
- `Hardware/NPU/TestBench/PoolCompareUnit_tb.sv`
- `Hardware/NPU/TestBench/ConvMacUnit_tb.sv`

Makefile target:

```sh
cd Hardware/NPU/TestBench
tcsh -c 'make primitive_units_vcs >& primitive_units_vcs.log'
```

## ISS Alignment

The primitive behavior is aligned to `Compiler/npu_iss.py`:

```text
activation storage: uint8
activation zero point: 128
signed activation domain: uint8 - 128
weight domain: signed int8
bias domain: signed int32
MAC accumulation: signed 64-bit in these primitives
requant shift: arithmetic right shift, no rounding
final clamp: signed [-128, 127]
final pack: clipped_signed + 128
ADD: ((lhs-128) >>> LHS) + ((rhs-128) >>> RHS), clamp, +128
POOL compare: signed activation domain, padding = -128 / uint8 0
SiLU: round(q * sigmoid(clip(q, -30, 30)))
```

## Bit-Width Decisions

### QuantizeUnit

- Input accumulator: signed 64-bit parameterized `ACC_WIDTH`.
- Shifted value: signed 64-bit arithmetic right shift.
- Clamp bounds: explicit signed 64-bit constants `-128` and `127`.
- Output signed value: signed int8 only after clamp.
- Packed output: explicit 9-bit `clipped + 128`, then uint8.

### ActivationUnit

- Input/output: signed 64-bit parameterized `ACC_WIDTH`.
- ReLU: explicit compare against signed zero.
- SiLU: functional raw-math implementation using `$exp`, with round-to-nearest-even to match numpy `round`.
- This SiLU implementation is for functional correctness first. Final hardware can replace it with LUT/fixed-point only after the golden contract is regenerated or formally approved.

### AddUnit

- Input bytes: uint8.
- Signed operands: signed int9 after subtracting zero point.
- Shifted operands: signed int18.
- Sum: signed int19.
- Clamp bounds: explicit signed int19 `-128` and `127`.
- Output pack: explicit 9-bit `clipped + 128`.

### PoolCompareUnit

- Current/candidate bytes: uint8.
- Compare values: signed int9 after subtracting zero point.
- Padding: uint8 `0`, equivalent to signed `-128`.
- Output: existing packed uint8 winner.

### ConvMacUnit

- Activation: uint8 -> signed int9.
- Weight: signed int8.
- Product: signed int18 with explicit 36-bit intermediate product.
- Bias: signed int32, explicitly sign-extended.
- Accumulator: signed 64-bit parameterized `ACC_WIDTH`.
- No MAC saturation. Final saturation belongs to `QuantizeUnit`.

## Verification Result

Command:

```sh
cd Hardware/NPU/TestBench
tcsh -c 'make primitive_units_vcs >& primitive_units_vcs.log'
```

Result:

```text
QuantizeUnit_tb PASS: 73 checks
ActivationUnit_tb PASS: 778 checks
AddUnit_tb PASS: 584 checks
PoolCompareUnit_tb PASS: 10 checks
ConvMacUnit_tb PASS: 6 checks
Primitive compute unit VCS regression PASS
```

Total checks: 1451.

The VCS log is:

```text
Hardware/NPU/TestBench/primitive_units_vcs.log
```

## Current Boundary

This is Gate B primitive verification only.

No `DummyExec` replacement was performed in this step. The next step is Phase 3:

```text
Decoder exec_* -> ComputeTop -> primitive blocks -> SRAM port -> exec_done
```

The first integration target should be a real first-CONV smoke test:

```text
pc=0 DMA_LD input
pc=1 DMA_LD first weights
pc=2 CONFIG
pc=3 real CONV
compare output against software golden for layer L0
```
