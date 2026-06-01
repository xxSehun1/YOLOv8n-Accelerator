`include "define.svh"

// ConvMacUnit
//
// One scalar MAC step for the CONV datapath:
//   act_s   = act_u8 - 128
//   product = act_s * weight_s8
//   psum_out = (clear ? 0 : psum_in) + product + optional bias
//
// Width policy:
//   activation: uint8 -> signed int9 after zero-point removal
//   weight    : signed int8
//   product   : signed int18, with a 36-bit intermediate product_full
//   bias      : signed int32, explicitly sign-extended
//   psum      : signed ACC_WIDTH, default 64 to mirror npu_iss.py int64
//   MAC accumulation does not saturate; QuantizeUnit performs the final clamp.
module ConvMacUnit #(
    parameter int ACC_WIDTH = 64
) (
    input  logic [7:0]                    act_u8,
    input  logic signed [7:0]             weight_s8,
    input  logic signed [ACC_WIDTH-1:0]   psum_in,
    input  logic                          clear,
    input  logic                          add_bias,
    input  logic signed [31:0]            bias_s32,
    output logic signed [8:0]             act_s9,
    output logic signed [17:0]            product_s18,
    output logic signed [ACC_WIDTH-1:0]   psum_out
);
    logic signed [17:0] act_ext18;
    logic signed [17:0] weight_ext18;
    logic signed [35:0] product_full;
    logic signed [ACC_WIDTH-1:0] base_ext;
    logic signed [ACC_WIDTH-1:0] product_ext;
    logic signed [ACC_WIDTH-1:0] bias_ext;

    always_comb begin
        act_s9       = $signed({1'b0, act_u8}) - 9'sd128;
        act_ext18    = {{9{act_s9[8]}}, act_s9};
        weight_ext18 = {{10{weight_s8[7]}}, weight_s8};
        product_full = act_ext18 * weight_ext18;

        // Product range is bounded by [-16256, 16384], so bits [17:0] are a
        // complete signed representation. The slice is the named pack point.
        product_s18 = product_full[17:0];

        base_ext    = clear ? '0 : psum_in;
        product_ext = {{(ACC_WIDTH-18){product_s18[17]}}, product_s18};
        bias_ext    = {{(ACC_WIDTH-32){bias_s32[31]}}, bias_s32};

        psum_out = base_ext + product_ext + (add_bias ? bias_ext : '0);
    end
endmodule
