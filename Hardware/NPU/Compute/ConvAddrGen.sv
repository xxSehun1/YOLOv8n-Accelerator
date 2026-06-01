`include "define.svh"

// ConvAddrGen
//
// Convolution address generator implemented as nested counters.
// This replaces software-style per-cycle division/modulo in ComputeTop.
//
// Counter order:
//   kx -> ky -> ic -> ow -> oh -> oc
//
// Memory layout:
//   activation: C,H,W contiguous bytes
//   weight    : OC,IC,KY,KX contiguous bytes
//   output    : OC,OH,OW contiguous bytes
module ConvAddrGen (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic        next_mac,
    output logic        conv_done,

    input  logic [15:0] in_h,
    input  logic [15:0] in_w,
    input  logic [15:0] in_c,
    input  logic [15:0] out_c,
    input  logic [3:0]  kernel,
    input  logic [3:0]  stride,
    input  logic [3:0]  pad,
    input  logic [31:0] in_addr_base,
    input  logic [31:0] wgt_addr_base,
    input  logic [31:0] out_addr_base,

    output logic [31:0] act_addr,
    output logic [31:0] wgt_addr,
    output logic [31:0] out_addr,
    output logic        is_pad_zero,
    output logic        pixel_done,

    output logic [15:0] dbg_oc,
    output logic [15:0] dbg_oh,
    output logic [15:0] dbg_ow,
    output logic [15:0] dbg_ic,
    output logic [3:0]  dbg_ky,
    output logic [3:0]  dbg_kx,
    output logic [15:0] dbg_out_h,
    output logic [15:0] dbg_out_w
);
    logic [3:0]  kx, ky;
    logic [15:0] ic, oc;
    logic [15:0] ow, oh;
    logic [15:0] out_w_max, out_h_max;

    logic [31:0] stride_eff;
    logic signed [31:0] in_x, in_y;

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
            ic <= '0;
            ow <= '0;
            oh <= '0;
            oc <= '0;
            conv_done <= 1'b0;
            if (start) begin
                out_w_max <= calc_out_dim(in_w, pad, kernel, stride);
                out_h_max <= calc_out_dim(in_h, pad, kernel, stride);
            end else begin
                out_w_max <= '0;
                out_h_max <= '0;
            end
        end else if (next_mac && !conv_done) begin
            if (kx == kernel - 4'd1) begin
                kx <= '0;
                if (ky == kernel - 4'd1) begin
                    ky <= '0;
                    if (ic == in_c - 16'd1) begin
                        ic <= '0;
                        if (ow == out_w_max - 16'd1) begin
                            ow <= '0;
                            if (oh == out_h_max - 16'd1) begin
                                oh <= '0;
                                if (oc == out_c - 16'd1) begin
                                    conv_done <= 1'b1;
                                end else begin
                                    oc <= oc + 16'd1;
                                end
                            end else begin
                                oh <= oh + 16'd1;
                            end
                        end else begin
                            ow <= ow + 16'd1;
                        end
                    end else begin
                        ic <= ic + 16'd1;
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
                        (ky == kernel - 4'd1) &&
                        (ic == in_c - 16'd1);

    always_comb begin
        in_x = $signed({1'b0, ow}) * $signed(stride_eff)
             + $signed({28'd0, kx}) - $signed({28'd0, pad});
        in_y = $signed({1'b0, oh}) * $signed(stride_eff)
             + $signed({28'd0, ky}) - $signed({28'd0, pad});

        is_pad_zero = (in_x < 0) || (in_x >= $signed({16'd0, in_w})) ||
                      (in_y < 0) || (in_y >= $signed({16'd0, in_h}));

        act_addr = in_addr_base
                 + ({16'd0, ic} * {16'd0, in_h} * {16'd0, in_w})
                 + (in_y[31:0] * {16'd0, in_w})
                 + in_x[31:0];

        wgt_addr = wgt_addr_base
                 + ({16'd0, oc} * {16'd0, in_c} * {28'd0, kernel} * {28'd0, kernel})
                 + ({16'd0, ic} * {28'd0, kernel} * {28'd0, kernel})
                 + ({28'd0, ky} * {28'd0, kernel})
                 + {28'd0, kx};

        out_addr = out_addr_base
                 + ({16'd0, oc} * {16'd0, out_h_max} * {16'd0, out_w_max})
                 + ({16'd0, oh} * {16'd0, out_w_max})
                 + {16'd0, ow};
    end

    assign dbg_oc = oc;
    assign dbg_oh = oh;
    assign dbg_ow = ow;
    assign dbg_ic = ic;
    assign dbg_ky = ky;
    assign dbg_kx = kx;
    assign dbg_out_h = out_h_max;
    assign dbg_out_w = out_w_max;
endmodule
