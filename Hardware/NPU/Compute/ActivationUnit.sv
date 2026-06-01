`include "define.svh"

// ActivationUnit
//
// Matches npu_iss.py _activation(q, flags):
//   if SIGMOID and MULTIPLY: round(q * sigmoid(clip(q, -30, 30)))
//   else if RELU: max(q, 0)
//   else: q
//
// This phase intentionally uses real-valued $exp for functional correctness.
// The final hardware implementation can replace this with a LUT or fixed-point
// approximation only after regenerating/approving the golden contract.
module ActivationUnit #(
    parameter int ACC_WIDTH = 64,
    parameter bit FAST_INT_SILU = 1'b0
) (
    input  logic signed [ACC_WIDTH-1:0] q_in,
    input  logic        [11:0]          flags,
    output logic signed [ACC_WIDTH-1:0] q_out
);
    localparam logic signed [ACC_WIDTH-1:0] ZERO_EXT = 0;
    localparam logic signed [ACC_WIDTH-1:0] CLIP_MIN = -30;
    localparam logic signed [ACC_WIDTH-1:0] CLIP_MAX =  30;

    function automatic logic signed [ACC_WIDTH-1:0] round_nearest_even(input real x);
        real abs_x;
        real floor_abs;
        real frac;
        longint signed mag;
        longint signed rounded_mag;
        bit neg;
        begin
            neg       = (x < 0.0);
            abs_x     = neg ? -x : x;
            floor_abs = $floor(abs_x);
            mag       = $rtoi(floor_abs);
            frac      = abs_x - floor_abs;

            if (frac > 0.5) begin
                rounded_mag = mag + 1;
            end else if (frac < 0.5) begin
                rounded_mag = mag;
            end else begin
                rounded_mag = ((mag % 2) == 0) ? mag : (mag + 1);
            end

            round_nearest_even = neg ? -rounded_mag : rounded_mag;
        end
    endfunction

    function automatic logic signed [ACC_WIDTH-1:0] silu_raw(
        input logic signed [ACC_WIDTH-1:0] q
    );
        real q_real;
        real q_clip_real;
        real sigmoid;
        real product;
        begin
            q_real = q;
            if (q < CLIP_MIN) begin
                q_clip_real = -30.0;
            end else if (q > CLIP_MAX) begin
                q_clip_real = 30.0;
            end else begin
                q_clip_real = q;
            end

            sigmoid = 1.0 / (1.0 + $exp(-q_clip_real));
            product = q_real * sigmoid;
            silu_raw = round_nearest_even(product);
        end
    endfunction

    always_comb begin
        if (flags[`FLAG_SIGMOID] && flags[`FLAG_MULTIPLY]) begin
            if (FAST_INT_SILU) begin
                // For the current integer ISS contract, q is integral. Over
                // the generated backbone range, round(q * sigmoid(q)) is
                // exactly q for q > 0 and 0 for q <= 0. Gate C uses this
                // functional shortcut to avoid millions of $exp calls.
                q_out = (q_in < ZERO_EXT) ? ZERO_EXT : q_in;
            end else begin
                q_out = silu_raw(q_in);
            end
        end else if (flags[`FLAG_RELU]) begin
            q_out = (q_in < ZERO_EXT) ? ZERO_EXT : q_in;
        end else begin
            q_out = q_in;
        end
    end
endmodule
