`include "define.svh"

// QuantizeUnit
//
// Matches npu_iss.py integer post-MAC behavior:
//   shifted = acc >>> shift
//   clipped = clamp(shifted, -128, 127)
//   packed = clipped + 128
//
// Width policy:
//   ACC_WIDTH      : explicit signed accumulator/input width, default 64 bits
//                    to mirror the ISS int64 reference model.
//   shifted_signed : ACC_WIDTH signed arithmetic-right-shift result.
//   clipped_signed : int8 result after explicit clamp.
//   packed_u8      : uint8 activation with zero point 128.
module QuantizeUnit #(
    parameter int ACC_WIDTH = 64
) (
    input  logic signed [ACC_WIDTH-1:0] acc_in,
    input  logic        [5:0]           shift,
    output logic signed [ACC_WIDTH-1:0] shifted_signed,
    output logic signed [7:0]           clipped_signed,
    output logic        [7:0]           packed_u8
);
    localparam logic signed [ACC_WIDTH-1:0] INT8_MIN_EXT = -128;
    localparam logic signed [ACC_WIDTH-1:0] INT8_MAX_EXT =  127;

    logic signed [8:0] zp_sum;

    always_comb begin
        shifted_signed = acc_in >>> shift;

        if (shifted_signed > INT8_MAX_EXT) begin
            clipped_signed = 8'sd127;
        end else if (shifted_signed < INT8_MIN_EXT) begin
            clipped_signed = -8'sd128;
        end else begin
            clipped_signed = shifted_signed[7:0];
        end

        zp_sum    = $signed({clipped_signed[7], clipped_signed}) + 9'sd128;
        packed_u8 = zp_sum[7:0];
    end
endmodule
