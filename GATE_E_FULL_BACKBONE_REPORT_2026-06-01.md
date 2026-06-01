# Gate E Full Backbone Verification Report

Date: 2026-06-01

## Result

Gate E PASS.

The complete 142-instruction YOLOv8n backbone program was simulated through `NPU_ctrl_top` with real `ComputeTop` execution paths. The final P3/P4/P5 output tensors were captured from DRAM after their final `DMA_ST` operations and compared byte-for-byte against the frozen Phase 0 golden binaries.

Combined mismatch count: `0`

## Command

Run directory:

```text
Hardware/NPU/TestBench
```

Command:

```text
tcsh -c 'make gate_e_full_backbone_vcs >& gate_e_full_backbone_vcs.log'
```

Final VCS log:

```text
Hardware/NPU/TestBench/gate_e_full_backbone_vcs.log
```

Testbench:

```text
Hardware/NPU/TestBench/NPU_gate_e_tb.sv
```

## Golden Contract

The testbench checks the final DRAM output regions against:

| Tensor | Golden file | Final DMA_ST PC | DRAM address | Size |
| --- | --- | ---: | ---: | ---: |
| P3 | `Build/golden_p3.bin` | 64 | `0x003f4000` | `0x00064000` |
| P4 | `Build/golden_p4.bin` | 99 | `0x004bc000` | `0x00032000` |
| P5 | `Build/golden_p5.bin` | 140 | `0x00545800` | `0x00019000` |

## Monitor Witness

Final tensor stores observed by monitor:

```text
[DMA_ST 6][pc=64] dram=0x003f4000 sram=0x00000000 size=0x00064000
[DMA_ST 10][pc=99] dram=0x004bc000 sram=0x00000000 size=0x00032000
[DMA_ST 17][pc=140] dram=0x00545800 sram=0x00000000 size=0x00019000
```

Final SPPF and P5 execution path observed:

```text
[EXEC_ACCEPT 33][pc=124] POOL H=20 W=20 IC=128 OC=128 out=0x00000000
[COMPUTE_DONE pc=124] POOL total=0x0000c800 out=0x00000000
[EXEC_ACCEPT 34][pc=126] POOL H=20 W=20 IC=128 OC=128 out=0x0000c800
[COMPUTE_DONE pc=126] POOL total=0x0000c800 out=0x0000c800
[EXEC_ACCEPT 35][pc=128] POOL H=20 W=20 IC=128 OC=128 out=0x00025800
[COMPUTE_DONE pc=128] POOL total=0x0000c800 out=0x00025800
[EXEC_ACCEPT 36][pc=139] CONV H=20 W=20 IC=512 OC=256 out=0x00000000
[COMPUTE_DONE pc=139] CONV total=0x00019000 out=0x00000000
```

HALT observed:

```text
[DECODE pc=141] opcode=HALT
[TB] HALT observed at 16167545325000
```

## Strict Sign-Off Checks

All checks below are direct monitor/TB results from `gate_e_full_backbone_vcs.log`.

```text
PASS: HALT reached
PASS: PC parked at HALT instruction
PASS: decoded every instruction including HALT
PASS: EXEC count matches generated ISA
PASS: CONV count matches generated ISA
PASS: POOL count matches generated ISA
PASS: ADD count matches generated ISA
PASS: DMA_LD count matches generated ISA
PASS: DMA_ST count matches generated ISA
PASS: weight DMA_LD count matches generated ISA
PASS: DMA_ST debug count matches generated ISA
PASS: no overloaded SRAM-copy DMA_LD was used
PASS: input DMA_LD was observed
PASS: P3 final DMA_ST observed
PASS: P4 final DMA_ST observed
PASS: P5 final DMA_ST observed
PASS: P3/P4/P5 combined mismatch_count is exactly 0
```

Expected hardware counters:

| Counter | Expected |
| --- | ---: |
| EXEC | 36 |
| CONV | 27 |
| POOL | 3 |
| ADD | 6 |
| DMA_LD | 46 |
| DMA_ST | 17 |
| Weight DMA_LD | 27 |
| SRAM-copy DMA_LD | 0 |

## Runtime

```text
VCS simulation time: 16167545325000 ps
VCS CPU Time: 902.220 seconds
Data structure size: 10.2 MB
```

The sign-off rerun used the cleaned `NPU_gate_e_tb.sv` timeout loop and did not emit the previous VCS `repeat` width truncation warning.

