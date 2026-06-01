`include "define.svh"

// NPU_ctrl_top: control/ISA/data-exchange integration target.
//
// This top is intentionally scoped to the outer-NPU responsibility:
//   ICache -> Decoder -> { DMA_ctrl, ComputeTop } -> SRAM/DRAM
//
// Gate C removes DummyExec from this integration path. ComputeTop is a
// correctness-first sequential engine for real numerical bring-up.
module NPU_ctrl_top (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,
    output logic         halted,

    // DRAM interface.
    output logic         dram_en,
    output logic         dram_we,
    output logic [31:0]  dram_addr,
    output logic [`DATA_BITS-1:0] dram_wdata,
    input  logic [`DATA_BITS-1:0] dram_rdata,

    // Debug/checkpoint outputs for the top-level TB.
    output logic [15:0]  debug_pc,
    output logic [3:0]   debug_opcode,
    output logic [63:0]  debug_opcode_name,
    output logic         debug_instr_req,
    output logic         debug_instr_valid,
    output logic         debug_exec_valid,
    output logic         debug_dma_valid,
    output logic [15:0]  debug_exec_count,
    output logic [15:0]  debug_conv_count,
    output logic [15:0]  debug_pool_count,
    output logic [15:0]  debug_add_count,
    output logic         debug_input_loaded,
    output logic [15:0]  debug_weight_load_count,
    output logic [15:0]  debug_sram_copy_count,
    output logic [15:0]  debug_store_count
);
    // ICache <-> Decoder.
    logic [15:0]  pc;
    logic         instr_req;
    logic [127:0] instr;
    logic         instr_valid;

    // Decoder -> ComputeTop.
    logic         exec_valid;
    logic [1:0]   exec_op;
    logic [15:0]  exec_in_h, exec_in_w, exec_in_c, exec_out_c;
    logic [31:0]  exec_in_addr, exec_wgt_addr, exec_out_addr;
    logic [11:0]  exec_flags;
    logic [3:0]   exec_stride, exec_pad, exec_kernel;
    logic [9:0]   exec_pconfig;
    logic [5:0]   exec_shift, exec_lhs_shift, exec_rhs_shift;
    logic         exec_done;

    // Decoder -> DMA_ctrl.
    logic         dma_valid, dma_is_store;
    logic [31:0]  dma_dram, dma_sram, dma_size;
    logic         dma_done;

    // SRAM ports.
    logic                              a_en, a_we;
    logic [`SRAM_ADDR_BITS-1:0]        a_addr;
    logic [`DATA_BITS-1:0]             a_wdata, a_rdata;
    logic                              b_en, b_we;
    logic [`SRAM_ADDR_BITS-1:0]        b_addr;
    logic [`DATA_BITS-1:0]             b_wdata, b_rdata;

    ICache i_cache (
        .clk(clk),
        .req(instr_req),
        .pc(pc),
        .instr(instr),
        .instr_valid(instr_valid)
    );

    Decoder i_decoder (
        .clk(clk), .rst(rst), .start(start),
        .pc(pc), .instr_req(instr_req), .instr(instr), .instr_valid(instr_valid),
        .exec_valid(exec_valid), .exec_op(exec_op),
        .exec_in_h(exec_in_h), .exec_in_w(exec_in_w),
        .exec_in_c(exec_in_c), .exec_out_c(exec_out_c),
        .exec_in_addr(exec_in_addr), .exec_wgt_addr(exec_wgt_addr),
        .exec_out_addr(exec_out_addr),
        .exec_flags(exec_flags),
        .exec_stride(exec_stride), .exec_pad(exec_pad), .exec_kernel(exec_kernel),
        .exec_pconfig(exec_pconfig),
        .exec_shift(exec_shift),
        .exec_lhs_shift(exec_lhs_shift), .exec_rhs_shift(exec_rhs_shift),
        .exec_done(exec_done),
        .dma_valid(dma_valid), .dma_is_store(dma_is_store),
        .dma_dram(dma_dram), .dma_sram(dma_sram), .dma_size(dma_size),
        .dma_done(dma_done),
        .halted(halted)
    );

    SRAM i_sram (
        .clk(clk),
        .a_en(a_en), .a_we(a_we), .a_addr(a_addr),
        .a_wdata(a_wdata), .a_rdata(a_rdata),
        .b_en(b_en), .b_we(b_we), .b_addr(b_addr),
        .b_wdata(b_wdata), .b_rdata(b_rdata)
    );

    DMA_ctrl i_dma (
        .clk(clk), .rst(rst),
        .dma_valid(dma_valid), .dma_is_store(dma_is_store),
        .dma_dram(dma_dram), .dma_sram(dma_sram), .dma_size(dma_size),
        .dma_done(dma_done),
        .dram_en(dram_en), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata), .dram_rdata(dram_rdata),
        .sram_en(a_en), .sram_we(a_we), .sram_addr(a_addr),
        .sram_wdata(a_wdata), .sram_rdata(a_rdata),
        .debug_input_loaded(debug_input_loaded),
        .debug_weight_load_count(debug_weight_load_count),
        .debug_sram_copy_count(debug_sram_copy_count),
        .debug_store_count(debug_store_count)
    );

    ComputeTop i_compute (
        .clk(clk), .rst(rst),
        .exec_valid(exec_valid), .exec_op(exec_op),
        .exec_in_h(exec_in_h), .exec_in_w(exec_in_w), .exec_in_c(exec_in_c),
        .exec_out_c(exec_out_c),
        .exec_in_addr(exec_in_addr), .exec_wgt_addr(exec_wgt_addr),
        .exec_out_addr(exec_out_addr),
        .exec_flags(exec_flags),
        .exec_stride(exec_stride), .exec_pad(exec_pad), .exec_kernel(exec_kernel),
        .exec_pconfig(exec_pconfig),
        .exec_shift(exec_shift),
        .exec_lhs_shift(exec_lhs_shift), .exec_rhs_shift(exec_rhs_shift),
        .exec_done(exec_done),
        .sram_en(b_en), .sram_we(b_we), .sram_addr(b_addr),
        .sram_wdata(b_wdata), .sram_rdata(b_rdata),
        .dma_sram_en(a_en), .dma_sram_we(a_we), .dma_sram_addr(a_addr),
        .dma_sram_wdata(a_wdata),
        .debug_exec_count(debug_exec_count),
        .debug_conv_count(debug_conv_count),
        .debug_pool_count(debug_pool_count),
        .debug_add_count(debug_add_count)
    );

    function automatic [63:0] opcode_ascii(input logic [3:0] op);
        case (op)
            `OP_CONV:   opcode_ascii = "CONV    ";
            `OP_POOL:   opcode_ascii = "POOL    ";
            `OP_CONCAT: opcode_ascii = "CONCAT  ";
            `OP_ADD:    opcode_ascii = "ADD     ";
            `OP_OTHER:  opcode_ascii = "OTHER   ";
            `OP_CONFIG: opcode_ascii = "CONFIG  ";
            `OP_BIAS:   opcode_ascii = "BIAS    ";
            `OP_DMA_LD: opcode_ascii = "DMA_LD  ";
            `OP_DMA_ST: opcode_ascii = "DMA_ST  ";
            `OP_ADDCFG: opcode_ascii = "ADDCFG  ";
            `OP_HALT:   opcode_ascii = "HALT    ";
            default:    opcode_ascii = "UNKNOWN ";
        endcase
    endfunction

    assign debug_pc          = pc;
    assign debug_opcode      = instr[127:124];
    assign debug_opcode_name = opcode_ascii(instr[127:124]);
    assign debug_instr_req   = instr_req;
    assign debug_instr_valid = instr_valid;
    assign debug_exec_valid  = exec_valid;
    assign debug_dma_valid   = dma_valid;

endmodule
