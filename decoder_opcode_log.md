# Decoder Opcode Unit Test Log

Source: Hardware/NPU/TestBench/decoder_opcode_vcs.log
Filtered: compile/banner messages removed; only unit-test witness lines are kept.

```text
== Decoder DMA_LD ==
  PASS: DMA_LD holds PC while waiting for dma_done
  PASS: DMA_LD drives dma_is_store=0
  PASS: DMA_LD dram field decoded
  PASS: DMA_LD sram field decoded
  PASS: DMA_LD size field decoded
  PASS: DMA_LD does not assert exec_valid
  PASS: DMA_LD advances to following HALT
== Decoder DMA_ST ==
  PASS: DMA_ST drives dma_is_store=1
  PASS: DMA_ST dram field decoded
  PASS: DMA_ST sram field decoded
  PASS: DMA_ST size field decoded
  PASS: DMA_ST does not assert exec_valid
== Decoder CONFIG + CONV ==
  PASS: CONV holds PC while waiting for exec_done
  PASS: CONV drives exec_op=0
  PASS: CONV consumes CONFIG H/W
  PASS: CONV consumes CONFIG C fields
  PASS: CONV consumes CONFIG pcfg/shift
  PASS: CONV input address decoded
  PASS: CONV weight address decoded
  PASS: CONV output address decoded
  PASS: CONV flags decoded
  PASS: CONV stride/pad/kernel decoded
  PASS: CONV does not assert dma_valid
== Decoder CONFIG + POOL ==
  PASS: POOL drives exec_op=1
  PASS: POOL consumes CONFIG H/W
  PASS: POOL consumes CONFIG output channels
  PASS: POOL pad/kernel decoded
== Decoder ADDCFG + CONFIG + ADD ==
  PASS: ADD holds PC while waiting for exec_done
  PASS: ADD drives exec_op=2
  PASS: ADD consumes ADDCFG lhs/rhs shifts
  PASS: ADD consumes CONFIG H/W
  PASS: ADD consumes CONFIG C fields
  PASS: ADD lhs address decoded
  PASS: ADD rhs address decoded through WGT field
  PASS: ADD output address decoded
== Decoder HALT ==
  PASS: HALT parks PC at halt instruction
  PASS: HALT asserts no command valid
== Decoder unsupported CONCAT ==
  PASS: CONCAT advanced PC to following HALT
  PASS: CONCAT asserted no command valid
== Decoder unsupported OTHER ==
  PASS: OTHER advanced PC to following HALT
  PASS: OTHER asserted no command valid
== Decoder unsupported BIAS ==
  PASS: BIAS advanced PC to following HALT
  PASS: BIAS asserted no command valid
== Decoder unsupported UNKNOWN_0xE ==
  PASS: UNKNOWN_0xE advanced PC to following HALT
  PASS: UNKNOWN_0xE asserted no command valid
== Decoder_opcode_tb PASS ==
```
