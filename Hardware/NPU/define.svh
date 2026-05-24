`ifndef DEFINE_SVH
`define DEFINE_SVH
// YOLOv8n NPU: global definitions.
//
// Values are derived from the existing RTL:
//   - PE.sv MAC loop iterates j = 0..3 over a word, so DATA_BITS = 32
//     (one 32-bit word packs 4 x int8 = 4 input channels).
//   - 16 x 16 PE array (system architecture slide).
// Place this file on the simulator include path (e.g. +incdir+Hardware/NPU).

// PE array geometry.
`define NUMS_PE_ROW    16
`define NUMS_PE_COL    16

// Datapath width. One word = 4 x int8 (4 input channels packed). PE.sv
// hard-codes the inner MAC loop to 4 bytes, so DATA_BITS must stay 32.
`define DATA_BITS      32
`define PSUM_BITS      32

// GIN / GON multicast tag widths.
// 16 columns/rows need IDs 0-15 plus one DEFAULT that must not collide,
// so 5 bits are required (DEFAULT = 31).  Must match gen_shared_hex.py.
`define XID_BITS       5
`define YID_BITS       5

// PE configuration bus (PE.sv reads out_ch_num from i_config[9:7]).
`define CONFIG_SIZE    32

// Instruction set: 128-bit instructions.
`define INSTR_BITS     128

// Opcode = instr[127:124].
`define OP_CONV        4'h1
`define OP_POOL        4'h2
`define OP_CONCAT      4'h3
`define OP_ADD         4'h4
`define OP_OTHER       4'h5
`define OP_CONFIG      4'h6
`define OP_BIAS        4'h7
`define OP_DMA_LD      4'h8
`define OP_DMA_ST      4'h9
`define OP_ADDCFG      4'hA
`define OP_HALT        4'hF

// FLAGS field bit indices (within EXEC_FLAGS).
`define FLAG_SIGMOID   0
`define FLAG_MULTIPLY  1
`define FLAG_RELU      2
`define FLAG_BIAS      3

// EXEC instruction fields (CONV / POOL / ADD / OTHER / HALT).
//   opcode | IN(32) | WGT(32) | OUT(32) | FLAGS(12) | STRIDE(4) | PAD(4) | KERNEL(4) | rsv(4)
`define EXEC_IN(i)      i[123:92]
`define EXEC_WGT(i)     i[91:60]
`define EXEC_OUT(i)     i[59:28]
`define EXEC_FLAGS(i)   i[27:16]
`define EXEC_STRIDE(i)  i[15:12]
`define EXEC_PAD(i)     i[11:8]
`define EXEC_KERNEL(i)  i[7:4]

// CONFIG instruction fields.
//   opcode | IN_H(16) | IN_W(16) | IN_C(16) | OUT_C(16) | STRIDE(4)
//          | rsv(40) | PE_CONFIG(10) | SHIFT(6)
`define CFG_IN_H(i)     i[123:108]
`define CFG_IN_W(i)     i[107:92]
`define CFG_IN_C(i)     i[91:76]
`define CFG_OUT_C(i)    i[75:60]
`define CFG_STRIDE(i)   i[59:56]
`define CFG_PCONFIG(i)  i[15:6]
`define CFG_SHIFT(i)    i[5:0]

// DMA instruction fields (DMA_LD / DMA_ST).
//   opcode | DRAM(32) | SRAM(32) | SIZE(32) | rsv(28)
`define DMA_DRAM(i)     i[123:92]
`define DMA_SRAM(i)     i[91:60]
`define DMA_SIZE(i)     i[59:28]

// ADDCFG instruction fields.
//   opcode | LHS_SHIFT(6) | RHS_SHIFT(6) | rsv(112)
`define ADDCFG_LHS(i)   i[123:118]
`define ADDCFG_RHS(i)   i[117:112]

// Memory map: DRAM (off-chip).
`define DRAM_INPUT_BASE   32'h0000_0000   // input image
`define DRAM_OUTPUT_BASE  32'h0020_0000   // backbone outputs P3/P4/P5
`define DRAM_WEIGHT_BASE  32'h0100_0000   // packed INT8 weights + INT32 bias

// Memory map: SRAM (4 MiB on-chip).
`define SRAM_SIZE         (4*1024*1024)
`define SRAM_ADDR_BITS    22              // 4 MiB byte-addressable
`define SRAM_WSTAGE_BASE  32'h0038_0000   // weight-staging area (2 x 256 KiB)
`define SRAM_WSTAGE_SLOT  (256*1024)

// Activation zero point (uint8 storage, symmetric range).
`define ACT_ZERO_POINT    8'd128

`endif
