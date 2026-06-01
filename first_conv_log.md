# First CONV TB Monitor Log

Source: Hardware/NPU/TestBench/first_conv_vcs.log
Filtered: compile/banner messages removed; only simulation witness lines are kept.

```text
[TB] loaded 1277680 weight bytes
== NPU_first_conv_tb: first CONV layer data/control check ==
[TB] start pulsed at 105000
[DECODE pc=0] DMA_LD dram=0x00000000 sram=0x00000000 size=0x0012c000
[DMA][pc=0]  DMA_LD DRAM_INPUT->SRAM dram=0x00000000 sram=0x00000000 size=0x0012c000
[DECODE pc=1] DMA_LD dram=0x01000000 sram=0x00380000 size=0x000001f0
[DMA][pc=1] DMA_LD DRAM_WEIGHT->SRAM dram=0x01000000 sram=0x00380000 size=0x000001f0
[DECODE pc=2] CONFIG H=640 W=640 IC=3 OC=16 stride=2 pcfg=0x07e shift=0x0a
[DECODE pc=3] CONV in=0x00000000 wgt=0x00380000 out=0x0012c000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=640 W=640 IC=3 OC=16 pcfg=0x07e shift=0x0a)
[EXEC_ACCEPT][pc=3] first CONV out=0x0012c000 H=640 W=640 OC=16 stride=2 pad=1 kernel=3
[EXEC_DONE][pc=3] first CONV dummy output complete
[TB] first CONV completed at 10242725000
== First CONV checkpoints ==
  PASS: exactly one EXEC op completed
  PASS: debug opcode alias checked through first CONV
  PASS: first EXEC was CONV
  PASS: no POOL executed
  PASS: no ADD executed
  PASS: input DMA_LD was observed
  PASS: one weight DMA_LD was observed
  PASS: no DMA_ST before first CONV completes
  PASS: input first word copied DRAM->SRAM
  PASS: input last word copied DRAM->SRAM
  PASS: weight first word copied DRAM->SRAM
  PASS: weight last word copied DRAM->SRAM
  PASS: first CONV dummy output first word matched
  PASS: first CONV dummy output last word matched
== NPU_first_conv_tb PASS ==
```
