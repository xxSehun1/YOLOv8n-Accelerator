`include "define.svh"

// PoolCompareUnit
//
// Scalar max-pool comparator matching npu_iss.py pool_max():
//   compare in signed activation domain (uint8 - 128)
//   padding contributes signed -128, which packs to uint8 0
//
// Width policy:
//   current/candidate bytes are widened to signed int9 before comparison.
//   Output remains uint8 and is copied only from an already packed candidate.
module PoolCompareUnit (
    input  logic       current_valid,
    input  logic [7:0] current_max_u8,
    input  logic       candidate_valid,
    input  logic       candidate_is_pad,
    input  logic [7:0] candidate_u8,
    output logic       max_valid,
    output logic [7:0] max_u8,
    output logic signed [8:0] current_signed,
    output logic signed [8:0] candidate_signed
);
    logic [7:0] candidate_effective_u8;

    always_comb begin
        candidate_effective_u8 = candidate_is_pad ? 8'd0 : candidate_u8;
        current_signed   = $signed({1'b0, current_max_u8}) - 9'sd128;
        candidate_signed = $signed({1'b0, candidate_effective_u8}) - 9'sd128;

        if (!current_valid) begin
            max_valid = candidate_valid;
            max_u8    = candidate_valid ? candidate_effective_u8 : 8'd0;
        end else if (!candidate_valid) begin
            max_valid = 1'b1;
            max_u8    = current_max_u8;
        end else if (candidate_signed > current_signed) begin
            max_valid = 1'b1;
            max_u8    = candidate_effective_u8;
        end else begin
            max_valid = 1'b1;
            max_u8    = current_max_u8;
        end
    end
endmodule
