`include "define.svh"
// PSUM_acc: 32-bit partial-sum accumulator (instantiate x16, one per
// output-channel lane).
//
// FSM: ACCUM -> COMPLETE -> RESET. Accumulates PE-array partial sums until the
// conv reduction is finished, then hands the 32-bit result to the PPU. The
// INT32 bias is folded into the accumulator seed at init time.
module PSUM_acc (
    input  logic                   clk,
    input  logic                   rst,

    input  logic                   init,        // load (start a new output px)
    input  logic                   accum_en,    // add psum_in this cycle
    input  logic                   last,        // this is the final partial sum
    input  logic signed [`PSUM_BITS-1:0] psum_in,
    input  logic signed [`PSUM_BITS-1:0] bias_in,  // INT32 bias, folded in at init (0 if none)

    output logic signed [`PSUM_BITS-1:0] psum_out,
    output logic                   complete     // reduction finished (1-cycle)
);
    logic signed [`PSUM_BITS-1:0] acc;
    logic                         done_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            acc    <= '0;
            done_q <= 1'b0;
        end else if (init) begin
            acc    <= psum_in + bias_in; // first partial sum + INT32 bias seed
            done_q <= last;
        end else if (accum_en) begin
            acc    <= acc + psum_in;    // subsequent partial sums accumulate
            done_q <= last;
        end else begin
            done_q <= 1'b0;
        end
    end

    assign psum_out = acc;
    assign complete = done_q;           // asserted the cycle after the last add
endmodule
