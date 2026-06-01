# Full NPU TB Monitor Witness

Date: 2026-05-31

Source: Hardware/NPU/TestBench/ctrl_full_vcs_monitor.log

This file is generated only from simulator monitor output. It is not copied from Build/full_instructions.txt.

```text
[DECODE pc=0] DMA_LD dram=0x00000000 sram=0x00000000 size=0x0012c000
[DMA 1][pc=0] DMA_LD DRAM_INPUT->SRAM dram=0x00000000 sram=0x00000000 size=0x0012c000
[DECODE pc=1] DMA_LD dram=0x01000000 sram=0x00380000 size=0x000001f0
[DMA 2][pc=1] DMA_LD DRAM_WEIGHT->SRAM dram=0x01000000 sram=0x00380000 size=0x000001f0
[DECODE pc=2] CONFIG in_h=640 in_w=640 in_c=3 out_c=16 stride=2 pcfg=0x07e shift=0x0a
[DECODE pc=3] CONV in=0x00000000 wgt=0x00380000 out=0x0012c000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=640 W=640 IC=3 OC=16 pcfg=0x07e shift=0x0a add_lhs=0x00 add_rhs=0x00)
[EXEC 1][pc=3] CONV out=0x0012c000 H=640 W=640 OC=16 stride=2 pad=1 kernel=3
[DECODE pc=4] DMA_LD dram=0x010001f0 sram=0x003c0000 size=0x00001280
[DMA 3][pc=4] DMA_LD DRAM_WEIGHT->SRAM dram=0x010001f0 sram=0x003c0000 size=0x00001280
[DECODE pc=5] CONFIG in_h=320 in_w=320 in_c=16 out_c=32 stride=2 pcfg=0x07f shift=0x09
[DECODE pc=6] CONV in=0x0012c000 wgt=0x003c0000 out=0x00000000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=320 W=320 IC=16 OC=32 pcfg=0x07f shift=0x09 add_lhs=0x00 add_rhs=0x00)
[EXEC 2][pc=6] CONV out=0x00000000 H=320 W=320 OC=32 stride=2 pad=1 kernel=3
[DECODE pc=7] DMA_LD dram=0x01001470 sram=0x00380000 size=0x00000480
[DMA 4][pc=7] DMA_LD DRAM_WEIGHT->SRAM dram=0x01001470 sram=0x00380000 size=0x00000480
[DECODE pc=8] CONFIG in_h=160 in_w=160 in_c=32 out_c=32 stride=1 pcfg=0x07f shift=0x07
[DECODE pc=9] CONV in=0x00000000 wgt=0x00380000 out=0x000c8000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=160 W=160 IC=32 OC=32 pcfg=0x07f shift=0x07 add_lhs=0x00 add_rhs=0x00)
[EXEC 3][pc=9] CONV out=0x000c8000 H=160 W=160 OC=32 stride=1 pad=0 kernel=1
[DECODE pc=10] DMA_LD dram=0x010018f0 sram=0x003c0000 size=0x00000940
[DMA 5][pc=10] DMA_LD DRAM_WEIGHT->SRAM dram=0x010018f0 sram=0x003c0000 size=0x00000940
[DECODE pc=11] CONFIG in_h=160 in_w=160 in_c=16 out_c=16 stride=1 pcfg=0x07f shift=0x08
[DECODE pc=12] CONV in=0x0012c000 wgt=0x003c0000 out=0x00000000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=160 W=160 IC=16 OC=16 pcfg=0x07f shift=0x08 add_lhs=0x00 add_rhs=0x00)
[EXEC 4][pc=12] CONV out=0x00000000 H=160 W=160 OC=16 stride=1 pad=1 kernel=3
[DECODE pc=13] DMA_LD dram=0x01002230 sram=0x00380000 size=0x00000940
[DMA 6][pc=13] DMA_LD DRAM_WEIGHT->SRAM dram=0x01002230 sram=0x00380000 size=0x00000940
[DECODE pc=14] CONFIG in_h=160 in_w=160 in_c=16 out_c=16 stride=1 pcfg=0x07f shift=0x09
[DECODE pc=15] CONV in=0x00000000 wgt=0x00380000 out=0x00064000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=160 W=160 IC=16 OC=16 pcfg=0x07f shift=0x09 add_lhs=0x00 add_rhs=0x00)
[EXEC 5][pc=15] CONV out=0x00064000 H=160 W=160 OC=16 stride=1 pad=1 kernel=3
[DECODE pc=16] ADDCFG lhs_shift=0x01 rhs_shift=0x00
[DECODE pc=17] CONFIG in_h=160 in_w=160 in_c=16 out_c=16 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=18] ADD in=0x0012c000 wgt=0x00064000 out=0x00000000 flags=0x000 stride=1 pad=0 kernel=1 uses_cfg(H=160 W=160 IC=16 OC=16 pcfg=0x000 shift=0x00 add_lhs=0x01 add_rhs=0x00)
[EXEC 6][pc=18] ADD out=0x00000000 H=160 W=160 OC=16 stride=1 pad=0 kernel=1
[DECODE pc=19] DMA_ST dram=0x00200000 sram=0x000c8000 size=0x000c8000
[DMA 7][pc=19] DMA_ST SRAM->DRAM dram=0x00200000 sram=0x000c8000 size=0x000c8000
[CHECKPOINT] concat staging store armed sram=0x000c8000 dram=0x00200000 word=0xd0030000
[CHECKPOINT] concat staging store matched dram=0x00200000 word=0xd0030000
[DECODE pc=20] DMA_ST dram=0x002c8000 sram=0x00000000 size=0x00064000
[DMA 8][pc=20] DMA_ST SRAM->DRAM dram=0x002c8000 sram=0x00000000 size=0x00064000
[DECODE pc=21] DMA_LD dram=0x00200000 sram=0x00190000 size=0x00064000
[DMA 9][pc=21] DMA_LD DRAM_STAGE->SRAM dram=0x00200000 sram=0x00190000 size=0x00064000
[CHECKPOINT] concat staging reload armed dram=0x00200000 sram=0x00190000
[CHECKPOINT] concat staging reload matched sram=0x00190000 word=0xd0030000
[DECODE pc=22] DMA_LD dram=0x00264000 sram=0x001f4000 size=0x00064000
[DMA 10][pc=22] DMA_LD DRAM_STAGE->SRAM dram=0x00264000 sram=0x001f4000 size=0x00064000
[DECODE pc=23] DMA_LD dram=0x002c8000 sram=0x00258000 size=0x00064000
[DMA 11][pc=23] DMA_LD DRAM_STAGE->SRAM dram=0x002c8000 sram=0x00258000 size=0x00064000
[DECODE pc=24] DMA_LD dram=0x01002b70 sram=0x003c0000 size=0x00000680
[DMA 12][pc=24] DMA_LD DRAM_WEIGHT->SRAM dram=0x01002b70 sram=0x003c0000 size=0x00000680
[DECODE pc=25] CONFIG in_h=160 in_w=160 in_c=48 out_c=32 stride=1 pcfg=0x07f shift=0x08
[DECODE pc=26] CONV in=0x00190000 wgt=0x003c0000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=160 W=160 IC=48 OC=32 pcfg=0x07f shift=0x08 add_lhs=0x01 add_rhs=0x00)
[EXEC 7][pc=26] CONV out=0x00000000 H=160 W=160 OC=32 stride=1 pad=0 kernel=1
[DECODE pc=27] DMA_LD dram=0x010031f0 sram=0x00380000 size=0x00004900
[DMA 13][pc=27] DMA_LD DRAM_WEIGHT->SRAM dram=0x010031f0 sram=0x00380000 size=0x00004900
[DECODE pc=28] CONFIG in_h=160 in_w=160 in_c=32 out_c=64 stride=2 pcfg=0x04f shift=0x0a
[DECODE pc=29] CONV in=0x00000000 wgt=0x00380000 out=0x000c8000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=160 W=160 IC=32 OC=64 pcfg=0x04f shift=0x0a add_lhs=0x01 add_rhs=0x00)
[EXEC 8][pc=29] CONV out=0x000c8000 H=160 W=160 OC=64 stride=2 pad=1 kernel=3
[DECODE pc=30] DMA_LD dram=0x01007af0 sram=0x003c0000 size=0x00001100
[DMA 14][pc=30] DMA_LD DRAM_WEIGHT->SRAM dram=0x01007af0 sram=0x003c0000 size=0x00001100
[DECODE pc=31] CONFIG in_h=80 in_w=80 in_c=64 out_c=64 stride=1 pcfg=0x04f shift=0x08
[DECODE pc=32] CONV in=0x000c8000 wgt=0x003c0000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=80 W=80 IC=64 OC=64 pcfg=0x04f shift=0x08 add_lhs=0x01 add_rhs=0x00)
[EXEC 9][pc=32] CONV out=0x00000000 H=80 W=80 OC=64 stride=1 pad=0 kernel=1
[DECODE pc=33] DMA_LD dram=0x01008bf0 sram=0x00380000 size=0x00002480
[DMA 15][pc=33] DMA_LD DRAM_WEIGHT->SRAM dram=0x01008bf0 sram=0x00380000 size=0x00002480
[DECODE pc=34] CONFIG in_h=80 in_w=80 in_c=32 out_c=32 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=35] CONV in=0x00032000 wgt=0x00380000 out=0x00064000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=80 W=80 IC=32 OC=32 pcfg=0x04f shift=0x09 add_lhs=0x01 add_rhs=0x00)
[EXEC 10][pc=35] CONV out=0x00064000 H=80 W=80 OC=32 stride=1 pad=1 kernel=3
[DECODE pc=36] DMA_LD dram=0x0100b070 sram=0x003c0000 size=0x00002480
[DMA 16][pc=36] DMA_LD DRAM_WEIGHT->SRAM dram=0x0100b070 sram=0x003c0000 size=0x00002480
[DECODE pc=37] CONFIG in_h=80 in_w=80 in_c=32 out_c=32 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=38] CONV in=0x00064000 wgt=0x003c0000 out=0x00096000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=80 W=80 IC=32 OC=32 pcfg=0x04f shift=0x09 add_lhs=0x01 add_rhs=0x00)
[EXEC 11][pc=38] CONV out=0x00096000 H=80 W=80 OC=32 stride=1 pad=1 kernel=3
[DECODE pc=39] ADDCFG lhs_shift=0x00 rhs_shift=0x00
[DECODE pc=40] CONFIG in_h=80 in_w=80 in_c=32 out_c=32 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=41] ADD in=0x00032000 wgt=0x00096000 out=0x00064000 flags=0x000 stride=1 pad=0 kernel=1 uses_cfg(H=80 W=80 IC=32 OC=32 pcfg=0x000 shift=0x00 add_lhs=0x00 add_rhs=0x00)
[EXEC 12][pc=41] ADD out=0x00064000 H=80 W=80 OC=32 stride=1 pad=0 kernel=1
[DECODE pc=42] DMA_LD dram=0x0100d4f0 sram=0x00380000 size=0x00002480
[DMA 17][pc=42] DMA_LD DRAM_WEIGHT->SRAM dram=0x0100d4f0 sram=0x00380000 size=0x00002480
[DECODE pc=43] CONFIG in_h=80 in_w=80 in_c=32 out_c=32 stride=1 pcfg=0x04f shift=0x0a
[DECODE pc=44] CONV in=0x00064000 wgt=0x00380000 out=0x00096000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=80 W=80 IC=32 OC=32 pcfg=0x04f shift=0x0a add_lhs=0x00 add_rhs=0x00)
[EXEC 13][pc=44] CONV out=0x00096000 H=80 W=80 OC=32 stride=1 pad=1 kernel=3
[DECODE pc=45] DMA_LD dram=0x0100f970 sram=0x003c0000 size=0x00002480
[DMA 18][pc=45] DMA_LD DRAM_WEIGHT->SRAM dram=0x0100f970 sram=0x003c0000 size=0x00002480
[DECODE pc=46] CONFIG in_h=80 in_w=80 in_c=32 out_c=32 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=47] CONV in=0x00096000 wgt=0x003c0000 out=0x000c8000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=80 W=80 IC=32 OC=32 pcfg=0x04f shift=0x09 add_lhs=0x00 add_rhs=0x00)
[EXEC 14][pc=47] CONV out=0x000c8000 H=80 W=80 OC=32 stride=1 pad=1 kernel=3
[DECODE pc=48] ADDCFG lhs_shift=0x01 rhs_shift=0x00
[DECODE pc=49] CONFIG in_h=80 in_w=80 in_c=32 out_c=32 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=50] ADD in=0x00064000 wgt=0x000c8000 out=0x00096000 flags=0x000 stride=1 pad=0 kernel=1 uses_cfg(H=80 W=80 IC=32 OC=32 pcfg=0x000 shift=0x00 add_lhs=0x01 add_rhs=0x00)
[EXEC 15][pc=50] ADD out=0x00096000 H=80 W=80 OC=32 stride=1 pad=0 kernel=1
[DECODE pc=51] DMA_ST dram=0x0032c000 sram=0x00000000 size=0x00064000
[DMA 19][pc=51] DMA_ST SRAM->DRAM dram=0x0032c000 sram=0x00000000 size=0x00064000
[DECODE pc=52] DMA_ST dram=0x00390000 sram=0x00064000 size=0x00032000
[DMA 20][pc=52] DMA_ST SRAM->DRAM dram=0x00390000 sram=0x00064000 size=0x00032000
[DECODE pc=53] DMA_ST dram=0x003c2000 sram=0x00096000 size=0x00032000
[DMA 21][pc=53] DMA_ST SRAM->DRAM dram=0x003c2000 sram=0x00096000 size=0x00032000
[DECODE pc=54] DMA_LD dram=0x0032c000 sram=0x000c8000 size=0x00032000
[DMA 22][pc=54] DMA_LD DRAM_STAGE->SRAM dram=0x0032c000 sram=0x000c8000 size=0x00032000
[DECODE pc=55] DMA_LD dram=0x0035e000 sram=0x000fa000 size=0x00032000
[DMA 23][pc=55] DMA_LD DRAM_STAGE->SRAM dram=0x0035e000 sram=0x000fa000 size=0x00032000
[DECODE pc=56] DMA_LD dram=0x00390000 sram=0x0012c000 size=0x00032000
[DMA 24][pc=56] DMA_LD DRAM_STAGE->SRAM dram=0x00390000 sram=0x0012c000 size=0x00032000
[DECODE pc=57] DMA_LD dram=0x003c2000 sram=0x0015e000 size=0x00032000
[DMA 25][pc=57] DMA_LD DRAM_STAGE->SRAM dram=0x003c2000 sram=0x0015e000 size=0x00032000
[DECODE pc=58] DMA_LD dram=0x01011df0 sram=0x00380000 size=0x00002100
[DMA 26][pc=58] DMA_LD DRAM_WEIGHT->SRAM dram=0x01011df0 sram=0x00380000 size=0x00002100
[DECODE pc=59] CONFIG in_h=80 in_w=80 in_c=128 out_c=64 stride=1 pcfg=0x04f shift=0x08
[DECODE pc=60] CONV in=0x000c8000 wgt=0x00380000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=80 W=80 IC=128 OC=64 pcfg=0x04f shift=0x08 add_lhs=0x01 add_rhs=0x00)
[EXEC 16][pc=60] CONV out=0x00000000 H=80 W=80 OC=64 stride=1 pad=0 kernel=1
[DECODE pc=61] DMA_LD dram=0x01013ef0 sram=0x003c0000 size=0x00012200
[DMA 27][pc=61] DMA_LD DRAM_WEIGHT->SRAM dram=0x01013ef0 sram=0x003c0000 size=0x00012200
[DECODE pc=62] CONFIG in_h=80 in_w=80 in_c=64 out_c=128 stride=2 pcfg=0x04f shift=0x0a
[DECODE pc=63] CONV in=0x00000000 wgt=0x003c0000 out=0x00064000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=80 W=80 IC=64 OC=128 pcfg=0x04f shift=0x0a add_lhs=0x01 add_rhs=0x00)
[EXEC 17][pc=63] CONV out=0x00064000 H=80 W=80 OC=128 stride=2 pad=1 kernel=3
[DECODE pc=64] DMA_ST dram=0x003f4000 sram=0x00000000 size=0x00064000
[DMA 28][pc=64] DMA_ST SRAM->DRAM dram=0x003f4000 sram=0x00000000 size=0x00064000
[DECODE pc=65] DMA_LD dram=0x010260f0 sram=0x00380000 size=0x00004200
[DMA 29][pc=65] DMA_LD DRAM_WEIGHT->SRAM dram=0x010260f0 sram=0x00380000 size=0x00004200
[DECODE pc=66] CONFIG in_h=40 in_w=40 in_c=128 out_c=128 stride=1 pcfg=0x04f shift=0x08
[DECODE pc=67] CONV in=0x00064000 wgt=0x00380000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=40 W=40 IC=128 OC=128 pcfg=0x04f shift=0x08 add_lhs=0x01 add_rhs=0x00)
[EXEC 18][pc=67] CONV out=0x00000000 H=40 W=40 OC=128 stride=1 pad=0 kernel=1
[DECODE pc=68] DMA_LD dram=0x0102a2f0 sram=0x003c0000 size=0x00009100
[DMA 30][pc=68] DMA_LD DRAM_WEIGHT->SRAM dram=0x0102a2f0 sram=0x003c0000 size=0x00009100
[DECODE pc=69] CONFIG in_h=40 in_w=40 in_c=64 out_c=64 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=70] CONV in=0x00019000 wgt=0x003c0000 out=0x00032000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=40 W=40 IC=64 OC=64 pcfg=0x04f shift=0x09 add_lhs=0x01 add_rhs=0x00)
[EXEC 19][pc=70] CONV out=0x00032000 H=40 W=40 OC=64 stride=1 pad=1 kernel=3
[DECODE pc=71] DMA_LD dram=0x010333f0 sram=0x00380000 size=0x00009100
[DMA 31][pc=71] DMA_LD DRAM_WEIGHT->SRAM dram=0x010333f0 sram=0x00380000 size=0x00009100
[DECODE pc=72] CONFIG in_h=40 in_w=40 in_c=64 out_c=64 stride=1 pcfg=0x04f shift=0x0a
[DECODE pc=73] CONV in=0x00032000 wgt=0x00380000 out=0x0004b000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=40 W=40 IC=64 OC=64 pcfg=0x04f shift=0x0a add_lhs=0x01 add_rhs=0x00)
[EXEC 20][pc=73] CONV out=0x0004b000 H=40 W=40 OC=64 stride=1 pad=1 kernel=3
[DECODE pc=74] ADDCFG lhs_shift=0x00 rhs_shift=0x00
[DECODE pc=75] CONFIG in_h=40 in_w=40 in_c=64 out_c=64 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=76] ADD in=0x00019000 wgt=0x0004b000 out=0x00032000 flags=0x000 stride=1 pad=0 kernel=1 uses_cfg(H=40 W=40 IC=64 OC=64 pcfg=0x000 shift=0x00 add_lhs=0x00 add_rhs=0x00)
[EXEC 21][pc=76] ADD out=0x00032000 H=40 W=40 OC=64 stride=1 pad=0 kernel=1
[DECODE pc=77] DMA_LD dram=0x0103c4f0 sram=0x003c0000 size=0x00009100
[DMA 32][pc=77] DMA_LD DRAM_WEIGHT->SRAM dram=0x0103c4f0 sram=0x003c0000 size=0x00009100
[DECODE pc=78] CONFIG in_h=40 in_w=40 in_c=64 out_c=64 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=79] CONV in=0x00032000 wgt=0x003c0000 out=0x0004b000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=40 W=40 IC=64 OC=64 pcfg=0x04f shift=0x09 add_lhs=0x00 add_rhs=0x00)
[EXEC 22][pc=79] CONV out=0x0004b000 H=40 W=40 OC=64 stride=1 pad=1 kernel=3
[DECODE pc=80] DMA_LD dram=0x010455f0 sram=0x00380000 size=0x00009100
[DMA 33][pc=80] DMA_LD DRAM_WEIGHT->SRAM dram=0x010455f0 sram=0x00380000 size=0x00009100
[DECODE pc=81] CONFIG in_h=40 in_w=40 in_c=64 out_c=64 stride=1 pcfg=0x04f shift=0x0a
[DECODE pc=82] CONV in=0x0004b000 wgt=0x00380000 out=0x00064000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=40 W=40 IC=64 OC=64 pcfg=0x04f shift=0x0a add_lhs=0x00 add_rhs=0x00)
[EXEC 23][pc=82] CONV out=0x00064000 H=40 W=40 OC=64 stride=1 pad=1 kernel=3
[DECODE pc=83] ADDCFG lhs_shift=0x01 rhs_shift=0x00
[DECODE pc=84] CONFIG in_h=40 in_w=40 in_c=64 out_c=64 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=85] ADD in=0x00032000 wgt=0x00064000 out=0x0004b000 flags=0x000 stride=1 pad=0 kernel=1 uses_cfg(H=40 W=40 IC=64 OC=64 pcfg=0x000 shift=0x00 add_lhs=0x01 add_rhs=0x00)
[EXEC 24][pc=85] ADD out=0x0004b000 H=40 W=40 OC=64 stride=1 pad=0 kernel=1
[DECODE pc=86] DMA_ST dram=0x00458000 sram=0x00000000 size=0x00032000
[DMA 34][pc=86] DMA_ST SRAM->DRAM dram=0x00458000 sram=0x00000000 size=0x00032000
[DECODE pc=87] DMA_ST dram=0x0048a000 sram=0x00032000 size=0x00019000
[DMA 35][pc=87] DMA_ST SRAM->DRAM dram=0x0048a000 sram=0x00032000 size=0x00019000
[DECODE pc=88] DMA_ST dram=0x004a3000 sram=0x0004b000 size=0x00019000
[DMA 36][pc=88] DMA_ST SRAM->DRAM dram=0x004a3000 sram=0x0004b000 size=0x00019000
[DECODE pc=89] DMA_LD dram=0x00458000 sram=0x00064000 size=0x00019000
[DMA 37][pc=89] DMA_LD DRAM_STAGE->SRAM dram=0x00458000 sram=0x00064000 size=0x00019000
[DECODE pc=90] DMA_LD dram=0x00471000 sram=0x0007d000 size=0x00019000
[DMA 38][pc=90] DMA_LD DRAM_STAGE->SRAM dram=0x00471000 sram=0x0007d000 size=0x00019000
[DECODE pc=91] DMA_LD dram=0x0048a000 sram=0x00096000 size=0x00019000
[DMA 39][pc=91] DMA_LD DRAM_STAGE->SRAM dram=0x0048a000 sram=0x00096000 size=0x00019000
[DECODE pc=92] DMA_LD dram=0x004a3000 sram=0x000af000 size=0x00019000
[DMA 40][pc=92] DMA_LD DRAM_STAGE->SRAM dram=0x004a3000 sram=0x000af000 size=0x00019000
[DECODE pc=93] DMA_LD dram=0x0104e6f0 sram=0x003c0000 size=0x00008200
[DMA 41][pc=93] DMA_LD DRAM_WEIGHT->SRAM dram=0x0104e6f0 sram=0x003c0000 size=0x00008200
[DECODE pc=94] CONFIG in_h=40 in_w=40 in_c=256 out_c=128 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=95] CONV in=0x00064000 wgt=0x003c0000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=40 W=40 IC=256 OC=128 pcfg=0x04f shift=0x09 add_lhs=0x01 add_rhs=0x00)
[EXEC 25][pc=95] CONV out=0x00000000 H=40 W=40 OC=128 stride=1 pad=0 kernel=1
[DECODE pc=96] DMA_LD dram=0x010568f0 sram=0x00380000 size=0x00048400
[DMA 42][pc=96] DMA_LD DRAM_WEIGHT->SRAM dram=0x010568f0 sram=0x00380000 size=0x00048400
[DECODE pc=97] CONFIG in_h=40 in_w=40 in_c=128 out_c=256 stride=2 pcfg=0x04f shift=0x0a
[DECODE pc=98] CONV in=0x00000000 wgt=0x00380000 out=0x00032000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=40 W=40 IC=128 OC=256 pcfg=0x04f shift=0x0a add_lhs=0x01 add_rhs=0x00)
[EXEC 26][pc=98] CONV out=0x00032000 H=40 W=40 OC=256 stride=2 pad=1 kernel=3
[DECODE pc=99] DMA_ST dram=0x004bc000 sram=0x00000000 size=0x00032000
[DMA 43][pc=99] DMA_ST SRAM->DRAM dram=0x004bc000 sram=0x00000000 size=0x00032000
[DECODE pc=100] DMA_LD dram=0x0109ecf0 sram=0x003c0000 size=0x00010400
[DMA 44][pc=100] DMA_LD DRAM_WEIGHT->SRAM dram=0x0109ecf0 sram=0x003c0000 size=0x00010400
[DECODE pc=101] CONFIG in_h=20 in_w=20 in_c=256 out_c=256 stride=1 pcfg=0x04f shift=0x0a
[DECODE pc=102] CONV in=0x00032000 wgt=0x003c0000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=20 W=20 IC=256 OC=256 pcfg=0x04f shift=0x0a add_lhs=0x01 add_rhs=0x00)
[EXEC 27][pc=102] CONV out=0x00000000 H=20 W=20 OC=256 stride=1 pad=0 kernel=1
[DECODE pc=103] DMA_LD dram=0x010af0f0 sram=0x00380000 size=0x00024200
[DMA 45][pc=103] DMA_LD DRAM_WEIGHT->SRAM dram=0x010af0f0 sram=0x00380000 size=0x00024200
[DECODE pc=104] CONFIG in_h=20 in_w=20 in_c=128 out_c=128 stride=1 pcfg=0x04f shift=0x0a
[DECODE pc=105] CONV in=0x0000c800 wgt=0x00380000 out=0x00019000 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=20 W=20 IC=128 OC=128 pcfg=0x04f shift=0x0a add_lhs=0x01 add_rhs=0x00)
[EXEC 28][pc=105] CONV out=0x00019000 H=20 W=20 OC=128 stride=1 pad=1 kernel=3
[DECODE pc=106] DMA_LD dram=0x010d32f0 sram=0x003c0000 size=0x00024200
[DMA 46][pc=106] DMA_LD DRAM_WEIGHT->SRAM dram=0x010d32f0 sram=0x003c0000 size=0x00024200
[DECODE pc=107] CONFIG in_h=20 in_w=20 in_c=128 out_c=128 stride=1 pcfg=0x04f shift=0x0b
[DECODE pc=108] CONV in=0x00019000 wgt=0x003c0000 out=0x00025800 flags=0x00b stride=1 pad=1 kernel=3 uses_cfg(H=20 W=20 IC=128 OC=128 pcfg=0x04f shift=0x0b add_lhs=0x01 add_rhs=0x00)
[EXEC 29][pc=108] CONV out=0x00025800 H=20 W=20 OC=128 stride=1 pad=1 kernel=3
[DECODE pc=109] ADDCFG lhs_shift=0x00 rhs_shift=0x00
[DECODE pc=110] CONFIG in_h=20 in_w=20 in_c=128 out_c=128 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=111] ADD in=0x0000c800 wgt=0x00025800 out=0x00019000 flags=0x000 stride=1 pad=0 kernel=1 uses_cfg(H=20 W=20 IC=128 OC=128 pcfg=0x000 shift=0x00 add_lhs=0x00 add_rhs=0x00)
[EXEC 30][pc=111] ADD out=0x00019000 H=20 W=20 OC=128 stride=1 pad=0 kernel=1
[DECODE pc=112] DMA_ST dram=0x004ee000 sram=0x00000000 size=0x00019000
[DMA 47][pc=112] DMA_ST SRAM->DRAM dram=0x004ee000 sram=0x00000000 size=0x00019000
[DECODE pc=113] DMA_ST dram=0x00507000 sram=0x00019000 size=0x0000c800
[DMA 48][pc=113] DMA_ST SRAM->DRAM dram=0x00507000 sram=0x00019000 size=0x0000c800
[DECODE pc=114] DMA_LD dram=0x004ee000 sram=0x00025800 size=0x0000c800
[DMA 49][pc=114] DMA_LD DRAM_STAGE->SRAM dram=0x004ee000 sram=0x00025800 size=0x0000c800
[DECODE pc=115] DMA_LD dram=0x004fa800 sram=0x00032000 size=0x0000c800
[DMA 50][pc=115] DMA_LD DRAM_STAGE->SRAM dram=0x004fa800 sram=0x00032000 size=0x0000c800
[DECODE pc=116] DMA_LD dram=0x00507000 sram=0x0003e800 size=0x0000c800
[DMA 51][pc=116] DMA_LD DRAM_STAGE->SRAM dram=0x00507000 sram=0x0003e800 size=0x0000c800
[DECODE pc=117] DMA_LD dram=0x010f74f0 sram=0x00380000 size=0x00018400
[DMA 52][pc=117] DMA_LD DRAM_WEIGHT->SRAM dram=0x010f74f0 sram=0x00380000 size=0x00018400
[DECODE pc=118] CONFIG in_h=20 in_w=20 in_c=384 out_c=256 stride=1 pcfg=0x04f shift=0x0a
[DECODE pc=119] CONV in=0x00025800 wgt=0x00380000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=20 W=20 IC=384 OC=256 pcfg=0x04f shift=0x0a add_lhs=0x00 add_rhs=0x00)
[EXEC 31][pc=119] CONV out=0x00000000 H=20 W=20 OC=256 stride=1 pad=0 kernel=1
[DECODE pc=120] DMA_LD dram=0x0110f8f0 sram=0x003c0000 size=0x00008200
[DMA 53][pc=120] DMA_LD DRAM_WEIGHT->SRAM dram=0x0110f8f0 sram=0x003c0000 size=0x00008200
[DECODE pc=121] CONFIG in_h=20 in_w=20 in_c=256 out_c=128 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=122] CONV in=0x00000000 wgt=0x003c0000 out=0x00019000 flags=0x008 stride=1 pad=0 kernel=1 uses_cfg(H=20 W=20 IC=256 OC=128 pcfg=0x04f shift=0x09 add_lhs=0x00 add_rhs=0x00)
[EXEC 32][pc=122] CONV out=0x00019000 H=20 W=20 OC=128 stride=1 pad=0 kernel=1
[DECODE pc=123] CONFIG in_h=20 in_w=20 in_c=128 out_c=128 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=124] POOL in=0x00019000 wgt=0x00000000 out=0x00000000 flags=0x000 stride=1 pad=2 kernel=5 uses_cfg(H=20 W=20 IC=128 OC=128 pcfg=0x000 shift=0x00 add_lhs=0x00 add_rhs=0x00)
[EXEC 33][pc=124] POOL out=0x00000000 H=20 W=20 OC=128 stride=1 pad=2 kernel=5
[DECODE pc=125] CONFIG in_h=20 in_w=20 in_c=128 out_c=128 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=126] POOL in=0x00000000 wgt=0x00000000 out=0x0000c800 flags=0x000 stride=1 pad=2 kernel=5 uses_cfg(H=20 W=20 IC=128 OC=128 pcfg=0x000 shift=0x00 add_lhs=0x00 add_rhs=0x00)
[EXEC 34][pc=126] POOL out=0x0000c800 H=20 W=20 OC=128 stride=1 pad=2 kernel=5
[DECODE pc=127] CONFIG in_h=20 in_w=20 in_c=128 out_c=128 stride=1 pcfg=0x000 shift=0x00
[DECODE pc=128] POOL in=0x0000c800 wgt=0x00000000 out=0x00025800 flags=0x000 stride=1 pad=2 kernel=5 uses_cfg(H=20 W=20 IC=128 OC=128 pcfg=0x000 shift=0x00 add_lhs=0x00 add_rhs=0x00)
[EXEC 35][pc=128] POOL out=0x00025800 H=20 W=20 OC=128 stride=1 pad=2 kernel=5
[DECODE pc=129] DMA_ST dram=0x00513800 sram=0x00019000 size=0x0000c800
[DMA 54][pc=129] DMA_ST SRAM->DRAM dram=0x00513800 sram=0x00019000 size=0x0000c800
[DECODE pc=130] DMA_ST dram=0x00520000 sram=0x00000000 size=0x0000c800
[DMA 55][pc=130] DMA_ST SRAM->DRAM dram=0x00520000 sram=0x00000000 size=0x0000c800
[DECODE pc=131] DMA_ST dram=0x0052c800 sram=0x0000c800 size=0x0000c800
[DMA 56][pc=131] DMA_ST SRAM->DRAM dram=0x0052c800 sram=0x0000c800 size=0x0000c800
[DECODE pc=132] DMA_ST dram=0x00539000 sram=0x00025800 size=0x0000c800
[DMA 57][pc=132] DMA_ST SRAM->DRAM dram=0x00539000 sram=0x00025800 size=0x0000c800
[DECODE pc=133] DMA_LD dram=0x00513800 sram=0x00032000 size=0x0000c800
[DMA 58][pc=133] DMA_LD DRAM_STAGE->SRAM dram=0x00513800 sram=0x00032000 size=0x0000c800
[DECODE pc=134] DMA_LD dram=0x00520000 sram=0x0003e800 size=0x0000c800
[DMA 59][pc=134] DMA_LD DRAM_STAGE->SRAM dram=0x00520000 sram=0x0003e800 size=0x0000c800
[DECODE pc=135] DMA_LD dram=0x0052c800 sram=0x0004b000 size=0x0000c800
[DMA 60][pc=135] DMA_LD DRAM_STAGE->SRAM dram=0x0052c800 sram=0x0004b000 size=0x0000c800
[DECODE pc=136] DMA_LD dram=0x00539000 sram=0x00057800 size=0x0000c800
[DMA 61][pc=136] DMA_LD DRAM_STAGE->SRAM dram=0x00539000 sram=0x00057800 size=0x0000c800
[DECODE pc=137] DMA_LD dram=0x01117af0 sram=0x00380000 size=0x00020400
[DMA 62][pc=137] DMA_LD DRAM_WEIGHT->SRAM dram=0x01117af0 sram=0x00380000 size=0x00020400
[DECODE pc=138] CONFIG in_h=20 in_w=20 in_c=512 out_c=256 stride=1 pcfg=0x04f shift=0x09
[DECODE pc=139] CONV in=0x00032000 wgt=0x00380000 out=0x00000000 flags=0x00b stride=1 pad=0 kernel=1 uses_cfg(H=20 W=20 IC=512 OC=256 pcfg=0x04f shift=0x09 add_lhs=0x00 add_rhs=0x00)
[EXEC 36][pc=139] CONV out=0x00000000 H=20 W=20 OC=256 stride=1 pad=0 kernel=1
[DECODE pc=140] DMA_ST dram=0x00545800 sram=0x00000000 size=0x00019000
[DMA 63][pc=140] DMA_ST SRAM->DRAM dram=0x00545800 sram=0x00000000 size=0x00019000
[DECODE pc=141] HALT
HALTED at 68729325000
== Checkpoints ==
pc=141 exec=36 conv=27 pool=3 add=6
dma_ld=46 dma_st=17 input_loaded=1 weight_ld=27 sram_copy=0 store=17
  PASS: HALT reached
  PASS: PC is parked at HALT instruction
  PASS: all generated EXEC ops accepted
  PASS: CONV count matches generated ISA
  PASS: POOL count matches generated ISA
  PASS: ADD count matches generated ISA
  PASS: DMA_LD count matches generated ISA
  PASS: input DRAM load was observed
  PASS: weight DMA_LD count matches generated ISA
  PASS: no overloaded SRAM-copy DMA_LD was used
  PASS: DMA_ST spill count matches generated ISA
  PASS: monitor saw every DMA_ST
  PASS: concat staging DMA_ST content was checked
  PASS: concat staging DMA_LD content was checked
  PASS: P3-like final output received nonzero dummy data
  PASS: P4-like final output received nonzero dummy data
  PASS: P5-like final output received nonzero dummy data
== NPU_ctrl_top_tb PASS ==
```
