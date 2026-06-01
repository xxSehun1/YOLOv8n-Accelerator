`include "define.svh"

// AddUnit
//
// Matches npu_iss.py add_int8():
//   lhs_s = lhs_u8 - 128
//   rhs_s = rhs_u8 - 128
//   sum   = (lhs_s >>> lhs_shift) + (rhs_s >>> rhs_shift)
//   out   = clamp(sum, -128, 127) + 128
//
// Width policy:
//   uint8 inputs are explicitly widened to signed int9 before zero-point
//   removal. Shifted operands use signed int18. Sum uses signed int19.
//   The only narrowing conversion is after explicit clamp to int8.
module AddUnit (
    input  logic [7:0] lhs_u8,
    input  logic [7:0] rhs_u8,
    input  logic [5:0] lhs_shift,
    input  logic [5:0] rhs_shift,
    output logic signed [8:0]  lhs_signed,
    output logic signed [8:0]  rhs_signed,
    output logic signed [18:0] sum_signed,
    output logic [7:0] out_u8
);
    localparam logic signed [18:0] INT8_MIN_EXT = -19'sd128;
    localparam logic signed [18:0] INT8_MAX_EXT =  19'sd127;

    logic signed [17:0] lhs_ext;
    logic signed [17:0] rhs_ext;
    logic signed [17:0] lhs_shifted;
    logic signed [17:0] rhs_shifted;
    logic signed [7:0]  clipped_signed;
    logic signed [8:0]  zp_sum;

    always_comb begin
        lhs_signed = $signed({1'b0, lhs_u8}) - 9'sd128;
        rhs_signed = $signed({1'b0, rhs_u8}) - 9'sd128;

        lhs_ext     = {{9{lhs_signed[8]}}, lhs_signed};
        rhs_ext     = {{9{rhs_signed[8]}}, rhs_signed};
        lhs_shifted = lhs_ext >>> lhs_shift;
        rhs_shifted = rhs_ext >>> rhs_shift;
        sum_signed  = {{1{lhs_shifted[17]}}, lhs_shifted}
                    + {{1{rhs_shifted[17]}}, rhs_shifted};

        if (sum_signed > INT8_MAX_EXT) begin
            clipped_signed = 8'sd127;
        end else if (sum_signed < INT8_MIN_EXT) begin
            clipped_signed = -8'sd128;
        end else begin
            clipped_signed = sum_signed[7:0];
        end

        zp_sum = $signed({clipped_signed[7], clipped_signed}) + 9'sd128;
        out_u8 = zp_sum[7:0];
    end
endmodule
