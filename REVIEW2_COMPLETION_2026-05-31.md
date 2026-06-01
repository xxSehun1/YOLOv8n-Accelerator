# Review2 Completion Report

Date: 2026-05-31

## Review2 Requirements

Review2 required four corrections before continuing real RTL work:

1. Clearly state the compiler/RTL responsibility boundary.
2. Do not treat a sequential correctness-first ComputeTop as final accelerator sign-off.
3. Require the final P3/P4/P5 bit-exact result to come from the real systolic/PE datapath with PingPong/buffer integration.
4. Explicitly define arithmetic widths and overflow/underflow behavior before primitive math RTL implementation.

## Implemented Changes

### PLAN2.md

Updated the plan to explicitly define:

- Compiler owns BatchNorm folding, Split/Concat lowering, activation flags, shape/weight/bias layout, and generated ISA.
- RTL executes the emitted ISA only; RTL must not infer graph-level YOLO structure.
- Sequential correctness-first ComputeTop is only a bring-up/debug reference.
- Final full-backbone sign-off must use the real parallel systolic/PE datapath integrated with PingPong_Ctrl, Weight_Buffer, IOMap_Buffer, Line_Buffer, PE_array, OpsumCollector, and PPU.
- Arithmetic RTL must define signedness, internal width, shift behavior, saturation/clipping, packing, and overflow/underflow handling explicitly. Implicit Verilog truncation is not acceptable.

### Compiler/npu_iss.py

Updated DMA_LD behavior to match the current generated ISA:

- DMA_LD is now always DRAM -> SRAM.
- The old overloaded DMA_LD SRAM -> SRAM concat behavior was removed.
- Current concat lowering uses DRAM staging: DMA_ST producer slice to DRAM, then DMA_LD DRAM stage into the concat SRAM destination.

### Compiler/validation.py

Extended validation so Phase 0 can freeze real golden outputs:

- Runs ONNX/TVM golden graph and ISS.
- Compares all 36 backbone compute layers byte-exact.
- After every layer matches, writes frozen output binaries:
  - `Build/golden_p3.bin`
  - `Build/golden_p4.bin`
  - `Build/golden_p5.bin`
- Writes `Build/golden_contract.md` with source artifact hashes, output layer mapping, shapes, byte sizes, final DMA_ST locations, and output hashes.

### Compiler/phase0_audit.py

Added strict Phase 0 audit:

- Checks required generated artifacts.
- Checks ISA structure and op counts.
- Confirms no old low-address overloaded DMA_LD concat pattern exists.
- Checks frozen golden files exist with exact byte sizes.
- Prints SHA256 for all source and golden artifacts.

### Compiler/makefile

Added:

- `PYTHON ?= python3`
- `TEST_DATA_ROOT_PATH ?= /tmp/tvm_test_data` so TVM does not try to write under the read-only home cache.
- `phase0`
- `phase0-strict`

### .gitignore

Updated the Build ignore rule so the frozen Phase 0 contract files are visible to git:

- `Build/golden_contract.md`
- `Build/golden_p3.bin`
- `Build/golden_p4.bin`
- `Build/golden_p5.bin`

Large intermediate files such as `Build/iss_layers.npz` remain ignored/generated.

## Frozen Golden Contract

The frozen contract is generated from a fixed random uint8 input:

- Input seed: numpy `default_rng(seed=0)`
- Input shape: `(3, 640, 640)`
- Output layout: CHW contiguous uint8
- Zero point: 128

Frozen outputs:

| Output | Layer | Shape | Bytes | Final DMA_ST DRAM | SHA256 |
|---|---:|---:|---:|---:|---|
| P3 | L15 CONV | 64x80x80 | 409600 | 0x003F4000 | 6301b628e76bd6b05364a60616b63a85d75892e14d427690fdad3f554ddc63a8 |
| P4 | L24 CONV | 128x40x40 | 204800 | 0x004BC000 | 18496400113eb02906871373a6820f1f24ec78aae48104aa012c92ad29c3cc20 |
| P5 | L35 CONV | 256x20x20 | 102400 | 0x00545800 | 672a90e1d8454d8e39c12b36db746229a1e601ce956f5ff7b3cf808a70242396 |

## Verification Run

### Compiler / Golden Validation

Command:

```sh
cd Compiler
make PYTHON=/tmp/aoc-yolo-venv/bin/python valid
```

Result:

- PASS: 36 golden layers and 36 ISS layers.
- PASS: every CONV / ADD / POOL layer matched byte-exact.
- PASS: frozen golden contract was written.

### Phase 0 Strict Audit

Command:

```sh
cd Compiler
make PYTHON=/tmp/aoc-yolo-venv/bin/python phase0-strict
```

Result:

- PASS: generated artifacts exist.
- PASS: instruction count is 142.
- PASS: final instruction is HALT.
- PASS: DMA_LD=46, DMA_ST=17.
- PASS: CONV=27, POOL=3, ADD=6.
- PASS: no old overloaded DMA_LD concat pattern.
- PASS: frozen golden contract files exist and match exact sizes.

### RTL / TB Regression

Commands:

```sh
cd Hardware/NPU/TestBench
tcsh -c 'make decoder_opcode_vcs >& decoder_opcode_vcs.log'
tcsh -c 'make dma_ctrl_unit_vcs >& dma_ctrl_unit_vcs.log'
tcsh -c 'make first_conv_vcs_fsdb >& first_conv_vcs_fsdb.log'
tcsh -c 'make ctrl_full_vcs_fsdb >& ctrl_full_vcs_fsdb.log'
```

Results:

- PASS: `Decoder_opcode_tb`
- PASS: `DMA_ctrl_unit_tb`
- PASS: `NPU_first_conv_tb`
- PASS: `NPU_ctrl_top_tb`
- FSDB generated:
  - `Hardware/NPU/TestBench/npu_first_conv.fsdb`
  - `Hardware/NPU/TestBench/npu_ctrl_top.fsdb`

Full-control witness:

- HALT reached at pc=141.
- exec=36, conv=27, pool=3, add=6.
- dma_ld=46, dma_st=17.
- input load observed.
- weight DMA_LD count matched generated ISA.
- no overloaded SRAM-copy DMA_LD was used.
- concat staging DMA_ST and DMA_LD content checks passed.
- P3/P4/P5 dummy final output regions became nonzero.

## Important Boundary

The current `NPU_ctrl_top` regression still uses `DummyExec`. This verifies the external control flow, decoder, DMA data movement, ICache fetch, SRAM/DRAM traffic, monitor coverage, and HALT behavior against the generated ISA.

It is not final numerical RTL sign-off. Final completion still requires replacing DummyExec with the real systolic/PE datapath and comparing real RTL P3/P4/P5 bytes against the frozen golden files above.
