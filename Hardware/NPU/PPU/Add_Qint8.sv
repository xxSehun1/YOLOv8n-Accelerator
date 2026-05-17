`include "define.svh"
// Add_Qint8: residual element-wise add unit.
//
// Computes the C2f Bottleneck shortcut out = x + conv2(conv1(x)) in the
// quantised domain. Activations are uint8 with zero-point 128; each operand is
// rescaled to the output scale by a power-of-2 right shift (from ADDCFG),
// matching the shift-based PostQuant unit.
//
//   out_q = sat( ((a_q-128) >>> LHS) + ((b_q-128) >>> RHS) ) + 128
//
// Purely combinational per element; wrap with a streaming FSM that feeds
// IN_C*IN_H*IN_W elements.
module Add_Qint8 (
    input  logic [7:0] a_in,        // operand A  (uint8, zp = 128)
    input  logic [7:0] b_in,        // operand B  (uint8, zp = 128)
    input  logic [5:0] lhs_shift,   // ADDCFG LHS: right shift for operand A
    input  logic [5:0] rhs_shift,   // ADDCFG RHS: right shift for operand B
    output logic [7:0] data_out     // result    (uint8, zp = 128)
);
    logic signed [8:0]  a_s,  b_s;     // operands after zero-point removal
    logic signed [16:0] a_sh, b_sh;    // operands after requant shift
    logic signed [17:0] sum;
    logic signed [7:0]  sat;

    always_comb begin
        // Strip zero point -> signed.
        a_s = $signed({1'b0, a_in}) - 9'sd128;
        b_s = $signed({1'b0, b_in}) - 9'sd128;

        // Per-operand requantisation (arithmetic right shift).
        a_sh = $signed(a_s) >>> lhs_shift;
        b_sh = $signed(b_s) >>> rhs_shift;
        sum  = a_sh + b_sh;

        // Saturate to int8.
        if      (sum >  18'sd127)  sat = 8'sd127;
        else if (sum < -18'sd128)  sat = -8'sd128;
        else                       sat = sum[7:0];

        // Restore zero point -> uint8.
        data_out = sat + 8'd128;
    end
endmodule
