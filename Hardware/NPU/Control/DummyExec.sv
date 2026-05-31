`include "define.svh"

// DummyExec: simulation-only stand-in for the compute subsystem.
//
// It accepts the Decoder's EXEC contract, writes a deterministic signature over
// the requested output feature-map region, and pulses exec_done. This lets the
// top-level control, I-cache, Decoder, DMA, concat-copy, and testbench data
// exchange run against the compiler-generated ISA before the real systolic
// controller/datapath is complete.
module DummyExec (
    input  logic         clk,
    input  logic         rst,

    input  logic         exec_valid,
    input  logic [1:0]   exec_op,          // 0 = CONV, 1 = POOL, 2 = ADD
    input  logic [15:0]  exec_in_h,
    input  logic [15:0]  exec_in_w,
    input  logic [15:0]  exec_out_c,
    input  logic [31:0]  exec_out_addr,
    input  logic [3:0]   exec_stride,
    input  logic [3:0]   exec_pad,
    input  logic [3:0]   exec_kernel,
    output logic         exec_done,

    // SRAM write port.
    output logic         sram_en,
    output logic         sram_we,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    output logic [`DATA_BITS-1:0]      sram_wdata,
    input  logic [`DATA_BITS-1:0]      sram_rdata,

    output logic [15:0]  debug_exec_count,
    output logic [15:0]  debug_conv_count,
    output logic [15:0]  debug_pool_count,
    output logic [15:0]  debug_add_count
);
    typedef enum logic [1:0] {S_IDLE, S_WRITE, S_DONE} state_t;
    state_t state, next;

    logic [31:0] base_addr;
    logic [31:0] total_words;
    logic [31:0] word_idx;
    logic [31:0] write_addr;
    logic [1:0]  op_latched;
    logic [7:0]  layer_id;

    function automatic [31:0] ceil_words(input [31:0] nbytes);
        ceil_words = (nbytes + 32'd3) >> 2;
    endfunction

    function automatic [31:0] output_words(
        input logic [1:0]  op,
        input logic [15:0] in_h,
        input logic [15:0] in_w,
        input logic [15:0] out_c,
        input logic [3:0]  stride_raw,
        input logic [3:0]  pad,
        input logic [3:0]  kernel
    );
        logic [31:0] stride;
        logic [31:0] out_h;
        logic [31:0] out_w;
        logic [31:0] padded_h;
        logic [31:0] padded_w;
        logic [31:0] bytes;
        begin
            stride = (stride_raw == 4'd0) ? 32'd1 : {28'd0, stride_raw};
            if (op == 2'd2) begin
                out_h = {16'd0, in_h};
                out_w = {16'd0, in_w};
            end else begin
                padded_h = {16'd0, in_h} + ({28'd0, pad} << 1);
                padded_w = {16'd0, in_w} + ({28'd0, pad} << 1);
                if (padded_h < {28'd0, kernel} || padded_w < {28'd0, kernel}) begin
                    out_h = 32'd1;
                    out_w = 32'd1;
                end else begin
                    out_h = ((padded_h - {28'd0, kernel}) / stride) + 32'd1;
                    out_w = ((padded_w - {28'd0, kernel}) / stride) + 32'd1;
                end
            end
            bytes = out_h * out_w * {16'd0, out_c};
            output_words = ceil_words(bytes);
        end
    endfunction

    always_comb begin
        next = state;
        case (state)
            S_IDLE:  if (exec_valid) next = S_WRITE;
            S_WRITE: if (word_idx == total_words - 32'd1) next = S_DONE;
            S_DONE:  next = S_IDLE;
            default: next = S_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            base_addr <= '0;
            total_words <= '0;
            word_idx <= '0;
            op_latched <= '0;
            layer_id <= '0;
            debug_exec_count <= '0;
            debug_conv_count <= '0;
            debug_pool_count <= '0;
            debug_add_count  <= '0;
        end else begin
            state <= next;
            case (state)
                S_IDLE: begin
                    word_idx <= '0;
                    if (exec_valid) begin
                        base_addr   <= exec_out_addr;
                        total_words <= output_words(exec_op, exec_in_h, exec_in_w,
                                                    exec_out_c, exec_stride,
                                                    exec_pad, exec_kernel);
                        op_latched  <= exec_op;
                        layer_id    <= debug_exec_count[7:0] + 8'd1;
                        debug_exec_count <= debug_exec_count + 16'd1;
                        case (exec_op)
                            2'd0: debug_conv_count <= debug_conv_count + 16'd1;
                            2'd1: debug_pool_count <= debug_pool_count + 16'd1;
                            2'd2: debug_add_count  <= debug_add_count  + 16'd1;
                            default: ;
                        endcase
                    end
                end
                S_WRITE: begin
                    word_idx <= word_idx + 32'd1;
                end
                default: ;
            endcase
        end
    end

    assign sram_en    = (state == S_WRITE);
    assign sram_we    = (state == S_WRITE);
    assign write_addr  = base_addr + (word_idx << 2);
    assign sram_addr   = write_addr[`SRAM_ADDR_BITS-1:0];
    assign sram_wdata = {8'hD0, layer_id, op_latched, word_idx[13:0]};
    assign exec_done  = (state == S_DONE);

    // Keep the read port consumed so lint tools do not flag it as accidental.
    logic unused_sram_rdata;
    assign unused_sram_rdata = ^sram_rdata;

endmodule
