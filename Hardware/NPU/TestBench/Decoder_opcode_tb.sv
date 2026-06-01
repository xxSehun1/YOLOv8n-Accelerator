`timescale 1ns/1ps
`include "define.svh"

module Decoder_opcode_tb;
    localparam int CLK_HALF = 5;
    localparam int PROGRAM_DEPTH = 8;

    logic clk = 1'b0;
    logic rst;
    logic start;

    logic [15:0]  pc;
    logic         instr_req;
    logic [127:0] instr;
    logic         instr_valid;

    logic         exec_valid;
    logic [1:0]   exec_op;
    logic [15:0]  exec_in_h, exec_in_w, exec_in_c, exec_out_c;
    logic [31:0]  exec_in_addr, exec_wgt_addr, exec_out_addr;
    logic [11:0]  exec_flags;
    logic [3:0]   exec_stride, exec_pad, exec_kernel;
    logic [9:0]   exec_pconfig;
    logic [5:0]   exec_shift, exec_lhs_shift, exec_rhs_shift;
    logic         exec_done;

    logic         dma_valid;
    logic         dma_is_store;
    logic [31:0]  dma_dram, dma_sram, dma_size;
    logic         dma_done;
    logic         halted;

    logic [127:0] prog_mem [0:PROGRAM_DEPTH-1];

    Decoder dut (
        .clk(clk), .rst(rst), .start(start),
        .pc(pc), .instr_req(instr_req), .instr(instr), .instr_valid(instr_valid),
        .exec_valid(exec_valid), .exec_op(exec_op),
        .exec_in_h(exec_in_h), .exec_in_w(exec_in_w),
        .exec_in_c(exec_in_c), .exec_out_c(exec_out_c),
        .exec_in_addr(exec_in_addr), .exec_wgt_addr(exec_wgt_addr),
        .exec_out_addr(exec_out_addr), .exec_flags(exec_flags),
        .exec_stride(exec_stride), .exec_pad(exec_pad), .exec_kernel(exec_kernel),
        .exec_pconfig(exec_pconfig), .exec_shift(exec_shift),
        .exec_lhs_shift(exec_lhs_shift), .exec_rhs_shift(exec_rhs_shift),
        .exec_done(exec_done),
        .dma_valid(dma_valid), .dma_is_store(dma_is_store),
        .dma_dram(dma_dram), .dma_sram(dma_sram), .dma_size(dma_size),
        .dma_done(dma_done), .halted(halted)
    );

    always #CLK_HALF clk = ~clk;

    assign instr       = prog_mem[pc];
    assign instr_valid = instr_req;

    function automatic logic [127:0] make_dma(
        input logic [3:0] op,
        input logic [31:0] dram,
        input logic [31:0] sram,
        input logic [31:0] size
    );
        make_dma = {op, dram, sram, size, 28'd0};
    endfunction

    function automatic logic [127:0] make_config(
        input logic [15:0] in_h,
        input logic [15:0] in_w,
        input logic [15:0] in_c,
        input logic [15:0] out_c,
        input logic [3:0]  stride,
        input logic [9:0]  pconfig,
        input logic [5:0]  shift
    );
        make_config = {`OP_CONFIG, in_h, in_w, in_c, out_c, stride,
                       40'd0, pconfig, shift};
    endfunction

    function automatic logic [127:0] make_addcfg(
        input logic [5:0] lhs,
        input logic [5:0] rhs
    );
        make_addcfg = {`OP_ADDCFG, lhs, rhs, 112'd0};
    endfunction

    function automatic logic [127:0] make_exec(
        input logic [3:0]  op,
        input logic [31:0] in_addr,
        input logic [31:0] wgt_addr,
        input logic [31:0] out_addr,
        input logic [11:0] flags,
        input logic [3:0]  stride,
        input logic [3:0]  pad,
        input logic [3:0]  kernel
    );
        make_exec = {op, in_addr, wgt_addr, out_addr, flags,
                     stride, pad, kernel, 4'd0};
    endfunction

    function automatic logic [127:0] make_halt;
        make_halt = {`OP_HALT, 124'd0};
    endfunction

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $fatal(1, "CHECK FAILED: %s", message);
        end
        $display("  PASS: %s", message);
    endtask

    task automatic clear_program;
        for (int i = 0; i < PROGRAM_DEPTH; i++) begin
            prog_mem[i] = make_halt();
        end
    endtask

    task automatic reset_decoder;
        begin
            rst = 1'b1;
            start = 1'b0;
            exec_done = 1'b0;
            dma_done = 1'b0;
            repeat (3) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic pulse_start;
        begin
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
        end
    endtask

    task automatic complete_dma;
        begin
            repeat (2) @(posedge clk);
            dma_done = 1'b1;
            @(posedge clk);
            dma_done = 1'b0;
        end
    endtask

    task automatic complete_exec;
        begin
            repeat (2) @(posedge clk);
            exec_done = 1'b1;
            @(posedge clk);
            exec_done = 1'b0;
        end
    endtask

    task automatic test_dma_ld;
        begin
            $display("== Decoder DMA_LD ==");
            clear_program();
            prog_mem[0] = make_dma(`OP_DMA_LD, 32'h1000_0100, 32'h0000_0200, 32'h0000_0040);
            prog_mem[1] = make_halt();
            reset_decoder();
            pulse_start();
            wait (dma_valid === 1'b1);
            check(pc == 16'd0, "DMA_LD holds PC while waiting for dma_done");
            check(dma_is_store === 1'b0, "DMA_LD drives dma_is_store=0");
            check(dma_dram == 32'h1000_0100, "DMA_LD dram field decoded");
            check(dma_sram == 32'h0000_0200, "DMA_LD sram field decoded");
            check(dma_size == 32'h0000_0040, "DMA_LD size field decoded");
            check(exec_valid === 1'b0, "DMA_LD does not assert exec_valid");
            complete_dma();
            wait (halted === 1'b1);
            check(pc == 16'd1, "DMA_LD advances to following HALT");
        end
    endtask

    task automatic test_dma_st;
        begin
            $display("== Decoder DMA_ST ==");
            clear_program();
            prog_mem[0] = make_dma(`OP_DMA_ST, 32'h2000_0100, 32'h0000_0300, 32'h0000_0080);
            prog_mem[1] = make_halt();
            reset_decoder();
            pulse_start();
            wait (dma_valid === 1'b1);
            check(dma_is_store === 1'b1, "DMA_ST drives dma_is_store=1");
            check(dma_dram == 32'h2000_0100, "DMA_ST dram field decoded");
            check(dma_sram == 32'h0000_0300, "DMA_ST sram field decoded");
            check(dma_size == 32'h0000_0080, "DMA_ST size field decoded");
            check(exec_valid === 1'b0, "DMA_ST does not assert exec_valid");
            complete_dma();
            wait (halted === 1'b1);
        end
    endtask

    task automatic test_config_conv;
        begin
            $display("== Decoder CONFIG + CONV ==");
            clear_program();
            prog_mem[0] = make_config(16'd640, 16'd640, 16'd3, 16'd16, 4'd2, 10'h07e, 6'h0a);
            prog_mem[1] = make_exec(`OP_CONV, 32'h0000_0000, 32'h0038_0000,
                                   32'h0012_c000, 12'h00b, 4'd2, 4'd1, 4'd3);
            prog_mem[2] = make_halt();
            reset_decoder();
            pulse_start();
            wait (exec_valid === 1'b1);
            check(pc == 16'd1, "CONV holds PC while waiting for exec_done");
            check(exec_op == 2'd0, "CONV drives exec_op=0");
            check(exec_in_h == 16'd640 && exec_in_w == 16'd640, "CONV consumes CONFIG H/W");
            check(exec_in_c == 16'd3 && exec_out_c == 16'd16, "CONV consumes CONFIG C fields");
            check(exec_pconfig == 10'h07e && exec_shift == 6'h0a, "CONV consumes CONFIG pcfg/shift");
            check(exec_in_addr == 32'h0000_0000, "CONV input address decoded");
            check(exec_wgt_addr == 32'h0038_0000, "CONV weight address decoded");
            check(exec_out_addr == 32'h0012_c000, "CONV output address decoded");
            check(exec_flags == 12'h00b, "CONV flags decoded");
            check(exec_stride == 4'd2 && exec_pad == 4'd1 && exec_kernel == 4'd3,
                  "CONV stride/pad/kernel decoded");
            check(dma_valid === 1'b0, "CONV does not assert dma_valid");
            complete_exec();
            wait (halted === 1'b1);
        end
    endtask

    task automatic test_config_pool;
        begin
            $display("== Decoder CONFIG + POOL ==");
            clear_program();
            prog_mem[0] = make_config(16'd20, 16'd20, 16'd128, 16'd128, 4'd1, 10'h000, 6'h00);
            prog_mem[1] = make_exec(`OP_POOL, 32'h0001_9000, 32'h0,
                                   32'h0000_0000, 12'h000, 4'd1, 4'd2, 4'd5);
            prog_mem[2] = make_halt();
            reset_decoder();
            pulse_start();
            wait (exec_valid === 1'b1);
            check(exec_op == 2'd1, "POOL drives exec_op=1");
            check(exec_in_h == 16'd20 && exec_in_w == 16'd20, "POOL consumes CONFIG H/W");
            check(exec_out_c == 16'd128, "POOL consumes CONFIG output channels");
            check(exec_pad == 4'd2 && exec_kernel == 4'd5, "POOL pad/kernel decoded");
            complete_exec();
            wait (halted === 1'b1);
        end
    endtask

    task automatic test_addcfg_config_add;
        begin
            $display("== Decoder ADDCFG + CONFIG + ADD ==");
            clear_program();
            prog_mem[0] = make_addcfg(6'h01, 6'h00);
            prog_mem[1] = make_config(16'd160, 16'd160, 16'd16, 16'd16, 4'd1, 10'h000, 6'h00);
            prog_mem[2] = make_exec(`OP_ADD, 32'h0012_c000, 32'h0006_4000,
                                   32'h0000_0000, 12'h000, 4'd1, 4'd0, 4'd1);
            prog_mem[3] = make_halt();
            reset_decoder();
            pulse_start();
            wait (exec_valid === 1'b1);
            check(pc == 16'd2, "ADD holds PC while waiting for exec_done");
            check(exec_op == 2'd2, "ADD drives exec_op=2");
            check(exec_lhs_shift == 6'h01 && exec_rhs_shift == 6'h00,
                  "ADD consumes ADDCFG lhs/rhs shifts");
            check(exec_in_h == 16'd160 && exec_in_w == 16'd160, "ADD consumes CONFIG H/W");
            check(exec_in_c == 16'd16 && exec_out_c == 16'd16, "ADD consumes CONFIG C fields");
            check(exec_in_addr == 32'h0012_c000, "ADD lhs address decoded");
            check(exec_wgt_addr == 32'h0006_4000, "ADD rhs address decoded through WGT field");
            check(exec_out_addr == 32'h0000_0000, "ADD output address decoded");
            complete_exec();
            wait (halted === 1'b1);
        end
    endtask

    task automatic test_halt;
        begin
            $display("== Decoder HALT ==");
            clear_program();
            prog_mem[0] = make_halt();
            reset_decoder();
            pulse_start();
            wait (halted === 1'b1);
            check(pc == 16'd0, "HALT parks PC at halt instruction");
            check(dma_valid === 1'b0 && exec_valid === 1'b0, "HALT asserts no command valid");
        end
    endtask

    task automatic test_unsupported(input logic [3:0] op, input string label);
        begin
            $display("== Decoder unsupported %s ==", label);
            clear_program();
            prog_mem[0] = {op, 124'h0123_4567_89ab_cdef_0123_4567_89ab_cde};
            prog_mem[1] = make_halt();
            reset_decoder();
            pulse_start();
            wait (halted === 1'b1);
            check(pc == 16'd1, {label, " advanced PC to following HALT"});
            check(dma_valid === 1'b0 && exec_valid === 1'b0, {label, " asserted no command valid"});
        end
    endtask

    initial begin
        clear_program();
        rst = 1'b1;
        start = 1'b0;
        exec_done = 1'b0;
        dma_done = 1'b0;

        test_dma_ld();
        test_dma_st();
        test_config_conv();
        test_config_pool();
        test_addcfg_config_add();
        test_halt();
        test_unsupported(`OP_CONCAT, "CONCAT");
        test_unsupported(`OP_OTHER,  "OTHER");
        test_unsupported(`OP_BIAS,   "BIAS");
        test_unsupported(4'hE,       "UNKNOWN_0xE");

        $display("== Decoder_opcode_tb PASS ==");
        $finish;
    end

endmodule
