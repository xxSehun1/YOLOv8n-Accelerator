`include "define.svh"

// PoolAddrGen
//
// Max-pool address generator implemented as nested counters.
//
// Counter order:
//   kx -> ky -> ow -> oh -> c
//
// Memory layout:
//   activation: C,H,W contiguous bytes
//   output    : C,OH,OW contiguous bytes
module PoolAddrGen (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic        next_candidate,
    output logic        pool_done,

    input  logic [15:0] in_h,
    input  logic [15:0] in_w,
    input  logic [15:0] in_c,
    input  logic [3:0]  kernel,
    input  logic [3:0]  stride,
    input  logic [3:0]  pad,
    input  logic [31:0] in_addr_base,
    input  logic [31:0] out_addr_base,

    output logic [31:0] act_addr,
    output logic [31:0] out_addr,
    output logic        is_pad_zero,
    output logic        pixel_done,

    output logic [15:0] dbg_c,
    output logic [15:0] dbg_oh,
    output logic [15:0] dbg_ow,
    output logic [3:0]  dbg_ky,
    output logic [3:0]  dbg_kx,
    output logic [15:0] dbg_out_h,
    output logic [15:0] dbg_out_w
);
    logic [3:0]  kx, ky;
    logic [15:0] c;
    logic [15:0] ow, oh;
    logic [15:0] out_w_max, out_h_max;

    logic [31:0] stride_eff;
    logic signed [31:0] in_x, in_y;
    logic [31:0] act_addr_calc;

    function automatic logic [15:0] calc_out_dim(
        input logic [15:0] in_dim,
        input logic [3:0]  pad_v,
        input logic [3:0]  kernel_v,
        input logic [3:0]  stride_v
    );
        logic [31:0] stride_tmp;
        logic [31:0] padded;
        begin
            stride_tmp = (stride_v == 4'd0) ? 32'd1 : {28'd0, stride_v};
            padded = {16'd0, in_dim} + ({28'd0, pad_v} << 1);
            if (padded < {28'd0, kernel_v}) begin
                calc_out_dim = 16'd0;
            end else begin
                calc_out_dim = 16'(((padded - {28'd0, kernel_v}) / stride_tmp) + 32'd1);
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst || start) begin
            kx <= '0;
            ky <= '0;
            ow <= '0;
            oh <= '0;
            c <= '0;
            pool_done <= 1'b0;
            if (start) begin
                out_w_max <= calc_out_dim(in_w, pad, kernel, stride);
                out_h_max <= calc_out_dim(in_h, pad, kernel, stride);
            end else begin
                out_w_max <= '0;
                out_h_max <= '0;
            end
        end else if (next_candidate && !pool_done) begin
            if (kx == kernel - 4'd1) begin
                kx <= '0;
                if (ky == kernel - 4'd1) begin
                    ky <= '0;
                    if (ow == out_w_max - 16'd1) begin
                        ow <= '0;
                        if (oh == out_h_max - 16'd1) begin
                            oh <= '0;
                            if (c == in_c - 16'd1) begin
                                pool_done <= 1'b1;
                            end else begin
                                c <= c + 16'd1;
                            end
                        end else begin
                            oh <= oh + 16'd1;
                        end
                    end else begin
                        ow <= ow + 16'd1;
                    end
                end else begin
                    ky <= ky + 4'd1;
                end
            end else begin
                kx <= kx + 4'd1;
            end
        end
    end

    assign stride_eff = (stride == 4'd0) ? 32'd1 : {28'd0, stride};
    assign pixel_done = (kx == kernel - 4'd1) &&
                        (ky == kernel - 4'd1);

    always_comb begin
        in_x = $signed({1'b0, ow}) * $signed(stride_eff)
             + $signed({28'd0, kx}) - $signed({28'd0, pad});
        in_y = $signed({1'b0, oh}) * $signed(stride_eff)
             + $signed({28'd0, ky}) - $signed({28'd0, pad});

        is_pad_zero = (in_x < 0) || (in_x >= $signed({16'd0, in_w})) ||
                      (in_y < 0) || (in_y >= $signed({16'd0, in_h}));

        act_addr_calc = in_addr_base
                      + ({16'd0, c} * {16'd0, in_h} * {16'd0, in_w})
                      + (in_y[31:0] * {16'd0, in_w})
                      + in_x[31:0];

        act_addr = is_pad_zero ? in_addr_base : act_addr_calc;

        out_addr = out_addr_base
                 + ({16'd0, c} * {16'd0, out_h_max} * {16'd0, out_w_max})
                 + ({16'd0, oh} * {16'd0, out_w_max})
                 + {16'd0, ow};
    end

    assign dbg_c = c;
    assign dbg_oh = oh;
    assign dbg_ow = ow;
    assign dbg_ky = ky;
    assign dbg_kx = kx;
    assign dbg_out_h = out_h_max;
    assign dbg_out_w = out_w_max;
endmodule
