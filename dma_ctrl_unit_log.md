# DMA_ctrl Unit Test Log

Source: Hardware/NPU/TestBench/dma_ctrl_unit_vcs.log
Filtered: compile/banner messages removed; only unit-test witness lines are kept.

```text
== DMA_ctrl_unit_tb: small DMA_LD ==
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA widx reached expected word count
  PASS: DMA returned to IDLE before next command
  PASS: small DMA_LD DRAM read count
  PASS: small DMA_LD SRAM write count
  PASS: small DMA_LD dma_done single pulse
  PASS: small DMA_LD first word copied
  PASS: small DMA_LD middle word copied
  PASS: small DMA_LD last word copied
  PASS: input/debug load flag set
  PASS: no SRAM-copy overload counted
== DMA_ctrl_unit_tb: small weight DMA_LD ==
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA widx reached expected word count
  PASS: DMA returned to IDLE before next command
  PASS: weight DMA_LD DRAM read count
  PASS: weight DMA_LD SRAM write count
  PASS: weight DMA_LD dma_done single pulse
  PASS: weight DMA_LD first word copied
  PASS: weight DMA_LD middle word copied
  PASS: weight DMA_LD last word copied
  PASS: weight load count incremented
  PASS: weight load did not count as SRAM copy
== DMA_ctrl_unit_tb: small DMA_ST ==
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA widx reached expected word count
  PASS: DMA returned to IDLE before next command
  PASS: small DMA_ST SRAM read count
  PASS: small DMA_ST DRAM write count
  PASS: small DMA_ST dma_done single pulse
  PASS: small DMA_ST first word copied
  PASS: small DMA_ST middle word copied
  PASS: small DMA_ST last word copied
  PASS: store count incremented
== DMA_ctrl_unit_tb: DRAM staging store/load pair ==
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA_ST S_RD reads SRAM
  PASS: DMA_ST SRAM read address sequence
  PASS: DMA_ST S_WR writes DRAM
  PASS: DMA_ST DRAM write address sequence
  PASS: DMA widx reached expected word count
  PASS: DMA returned to IDLE before next command
  PASS: staging DMA_ST SRAM read count
  PASS: staging DMA_ST DRAM write count
  PASS: staging DMA_ST dma_done single pulse
  PASS: staging DMA_ST first word copied
  PASS: staging DMA_ST middle word copied
  PASS: staging DMA_ST last word copied
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA_LD S_RD reads DRAM
  PASS: DMA_LD DRAM read address sequence
  PASS: DMA_LD S_WR writes SRAM
  PASS: DMA_LD SRAM write address sequence
  PASS: DMA widx reached expected word count
  PASS: DMA returned to IDLE before next command
  PASS: staging DMA_LD DRAM read count
  PASS: staging DMA_LD SRAM write count
  PASS: staging DMA_LD dma_done single pulse
  PASS: staging DMA_LD first word copied
  PASS: staging DMA_LD middle word copied
  PASS: staging DMA_LD last word copied
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
  PASS: staging SRAM source and reload destination match
== DMA_ctrl_unit_tb PASS ==
```
