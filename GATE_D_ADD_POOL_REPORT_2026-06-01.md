# Gate D ADD/POOL Integration Report - 2026-06-01

## Scope

Gate D replaces the remaining dummy compute behavior for `ADD` and `POOL` in `ComputeTop.sv`.

Implemented real datapaths:

- `CONV`: existing real scalar MAC path retained.
- `ADD`: real `AddUnit` path integrated.
- `POOL`: real `PoolCompareUnit` path integrated.

Added hardware-friendly address generators:

- `Hardware/NPU/Compute/AddAddrGen.sv`
- `Hardware/NPU/Compute/PoolAddrGen.sv`

The hot execution paths use counters and address accumulators. No per-cycle division or modulo was introduced.

`Hardware/NPU/Control/DummyExec.sv` was removed from the active RTL tree, and stale testbench references to `i_dummy_exec` were replaced with `i_compute`.

## RTL Changes

### `ComputeTop.sv`

`ComputeTop` now accepts all current generated compute ops:

```text
exec_op=0 CONV
exec_op=1 POOL
exec_op=2 ADD
```

The FSM selects the correct datapath per op:

- `CONV`: `ConvAddrGen` -> `ConvMacUnit` -> `QuantizeUnit` -> `ActivationUnit` -> SRAM writeback
- `POOL`: `PoolAddrGen` -> `PoolCompareUnit` -> SRAM writeback
- `ADD`: `AddAddrGen` -> `AddUnit` -> SRAM writeback

The DMA snoop mirror remains the compute-side read source so DMA-loaded data and compute-written data are both visible to subsequent compute ops.

### `AddAddrGen.sv`

ADD uses contiguous C,H,W byte layout:

```text
lhs_addr = lhs_base + byte_offset
rhs_addr = rhs_base + byte_offset
out_addr = out_base + byte_offset
```

It maintains `c/h/w` debug counters and increments by one output byte at a time.

### `PoolAddrGen.sv`

POOL uses nested counters:

```text
kx -> ky -> ow -> oh -> c
```

It computes:

- input candidate address
- output address
- padding flag
- output tensor traversal counters

## Golden Generation

Command:

```sh
cd Compiler
make PYTHON=/tmp/aoc-yolo-venv/bin/python gated-vectors
```

Generated files:

```text
Build/golden_first_add.bin                  a18d4d426f79cf6d3becad02c75aa8ab3da3904333d26643444d4cfb5d728293
Build/full_instructions_gate_d_first_add.txt 5953d9e7176731c4199f434cafab4acc5ef55c9887f6380dc5e2fd62dbb9fbe7
Build/npu_program_gate_d_first_add.hex      49d1de7a9c27898caba536ec2a4324f4a893ba2097448a5c471dc5996172fdfb
Build/golden_sppf_input.bin                 f36567884b09aef934a85cbbcafc32e0ed340dcfaa97e05791cd70a52cc0dd58
Build/golden_sppf_output.bin                672a90e1d8454d8e39c12b36db746229a1e601ce956f5ff7b3cf808a70242396
Build/full_instructions_gate_d_sppf.txt     564461cb841252914191bba922f1493cd3c8af9ffa96c9ebabe3975be2ced323
Build/npu_program_gate_d_sppf.hex           f423569185104560deea9175426053900f8989a38f288336404714723094a8cf
```

## Verification Commands

Run from `Hardware/NPU/TestBench`:

```sh
tcsh -c 'make primitive_units_vcs >& primitive_units_vcs.log'
tcsh -c 'make gate_c_first_conv_full_vcs >& gate_c_first_conv_full_vcs.log'
tcsh -c 'make gate_d_first_add_vcs >& gate_d_first_add_vcs.log'
tcsh -c 'make gate_d_sppf_vcs >& gate_d_sppf_vcs.log'
```

## Regression Results

Primitive units:

```text
==== Primitive compute unit VCS regression PASS ====
```

Full Gate C first CONV regression:

```text
PASS: Gate C full 640x640 first CONV output byte-for-byte matches ../../../Build/golden_l0_conv.bin
== NPU_first_conv_tb GATE C PASS ==
CPU Time: 31.060 seconds
```

## Gate D: First Residual ADD

Program scope:

- Full input `640x640x3`
- Instructions through the first residual ADD
- 5 real CONV ops
- 1 real ADD op
- HALT at pc=19

Important monitor witness:

```text
[EXEC_ACCEPT 1][pc=3] CONV H=640 W=640 IC=3 OC=16 out=0x0012c000
[EXEC_ACCEPT 2][pc=6] CONV H=320 W=320 IC=16 OC=32 out=0x00000000
[EXEC_ACCEPT 3][pc=9] CONV H=160 W=160 IC=32 OC=32 out=0x000c8000
[EXEC_ACCEPT 4][pc=12] CONV H=160 W=160 IC=16 OC=16 out=0x00000000
[EXEC_ACCEPT 5][pc=15] CONV H=160 W=160 IC=16 OC=16 out=0x00064000
[DECODE pc=18] ADD in=0x0012c000 wgt=0x00064000 out=0x00000000 stride=1 pad=0 kernel=1
[EXEC_ACCEPT 6][pc=18] ADD H=160 W=160 IC=16 OC=16 out=0x00000000
[COMPUTE_WRITE pc=18] ADD byte_offset=0x00063fff total=0x00064000
[DECODE pc=19] HALT
```

Result:

```text
PASS: Gate D first residual ADD output byte-for-byte matches ../../../Build/golden_first_add.bin
== NPU_gate_d_tb PASS: Gate D first residual ADD ==
CPU Time: 180.940 seconds
Data structure size: 9.6Mb
```

## Gate D: SPPF Block

Program scope:

- Block input is ISS golden tensor at the SPPF pool-chain entry.
- 3 real POOL ops
- 4 DMA_ST staging ops
- 4 DMA_LD concat reload ops
- 1 final SPPF 1x1 CONV
- HALT at pc=18

Important monitor witness:

```text
[EXEC_ACCEPT 1][pc=2] POOL H=20 W=20 IC=128 OC=128 out=0x00000000
[COMPUTE_WRITE pc=2] POOL byte_offset=0x0000c7ff total=0x0000c800
[EXEC_ACCEPT 2][pc=4] POOL H=20 W=20 IC=128 OC=128 out=0x0000c800
[COMPUTE_WRITE pc=4] POOL byte_offset=0x0000c7ff total=0x0000c800
[EXEC_ACCEPT 3][pc=6] POOL H=20 W=20 IC=128 OC=128 out=0x00025800
[COMPUTE_WRITE pc=6] POOL byte_offset=0x0000c7ff total=0x0000c800
[DMA pc=7] DMA_ST dram=0x00513800 sram=0x00019000 size=0x0000c800
[DMA pc=10] DMA_ST dram=0x00539000 sram=0x00025800 size=0x0000c800
[DMA pc=11] DMA_LD dram=0x00513800 sram=0x00032000 size=0x0000c800
[DMA pc=14] DMA_LD dram=0x00539000 sram=0x00057800 size=0x0000c800
[EXEC_ACCEPT 4][pc=17] CONV H=20 W=20 IC=512 OC=256 out=0x00000000
[COMPUTE_WRITE pc=17] CONV byte_offset=0x00018fff total=0x00019000
[DECODE pc=18] HALT
```

Result:

```text
PASS: Gate D SPPF block output byte-for-byte matches ../../../Build/golden_sppf_output.bin
== NPU_gate_d_tb PASS: Gate D SPPF block ==
CPU Time: 32.650 seconds
Data structure size: 4.5Mb
```

## Conclusion

Gate D targets passed:

- First residual ADD output is byte-exact against ISS golden.
- SPPF block output is byte-exact against ISS golden.
- Existing primitive-unit and full Gate C regressions still pass.

The remaining compute op types used by the generated YOLOv8n backbone ISA now have real datapaths in `ComputeTop.sv`.
