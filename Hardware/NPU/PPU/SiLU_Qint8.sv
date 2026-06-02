`include "define.svh"
// SiLU_Qint8: fused SiLU activation ( x * sigmoid(x) ).
//
// Applied in the PPU after PostQuant when FLAGS bit0|bit1 are set. Input and
// output are int8 (signed; the PPU adds the +128 zero point afterwards).
//
// Design: a single fixed 256-entry int8->int8 lookup table. The table is
// generated offline from a canonical SiLU input scale that the compiler
// targets for every SiLU layer, so one table serves the whole backbone and
// no per-layer scale needs to travel in the ISA.
module SiLU_Qint8 (
    input  logic               en,
    input  logic signed [7:0]  data_in,
    output logic signed [7:0]  data_out
);
    // Index is the raw int8 bit pattern:
    //   8'h00..8'h7f =>   0..127
    //   8'h80..8'hff => -128..-1
    //
    // Entries are generated from the frozen ISS definition:
    //   round_nearest_even(q * sigmoid(clip(q, -30, 30)))
    // For the current integer q domain this table is numerically equivalent
    // to ReLU, but the hardware implementation is intentionally a fixed LUT.
    localparam logic signed [7:0] SILU_LUT [0:255] = '{
        8'sd0, 8'sd1, 8'sd2, 8'sd3, 8'sd4, 8'sd5, 8'sd6, 8'sd7,
        8'sd8, 8'sd9, 8'sd10, 8'sd11, 8'sd12, 8'sd13, 8'sd14, 8'sd15,
        8'sd16, 8'sd17, 8'sd18, 8'sd19, 8'sd20, 8'sd21, 8'sd22, 8'sd23,
        8'sd24, 8'sd25, 8'sd26, 8'sd27, 8'sd28, 8'sd29, 8'sd30, 8'sd31,
        8'sd32, 8'sd33, 8'sd34, 8'sd35, 8'sd36, 8'sd37, 8'sd38, 8'sd39,
        8'sd40, 8'sd41, 8'sd42, 8'sd43, 8'sd44, 8'sd45, 8'sd46, 8'sd47,
        8'sd48, 8'sd49, 8'sd50, 8'sd51, 8'sd52, 8'sd53, 8'sd54, 8'sd55,
        8'sd56, 8'sd57, 8'sd58, 8'sd59, 8'sd60, 8'sd61, 8'sd62, 8'sd63,
        8'sd64, 8'sd65, 8'sd66, 8'sd67, 8'sd68, 8'sd69, 8'sd70, 8'sd71,
        8'sd72, 8'sd73, 8'sd74, 8'sd75, 8'sd76, 8'sd77, 8'sd78, 8'sd79,
        8'sd80, 8'sd81, 8'sd82, 8'sd83, 8'sd84, 8'sd85, 8'sd86, 8'sd87,
        8'sd88, 8'sd89, 8'sd90, 8'sd91, 8'sd92, 8'sd93, 8'sd94, 8'sd95,
        8'sd96, 8'sd97, 8'sd98, 8'sd99, 8'sd100, 8'sd101, 8'sd102, 8'sd103,
        8'sd104, 8'sd105, 8'sd106, 8'sd107, 8'sd108, 8'sd109, 8'sd110, 8'sd111,
        8'sd112, 8'sd113, 8'sd114, 8'sd115, 8'sd116, 8'sd117, 8'sd118, 8'sd119,
        8'sd120, 8'sd121, 8'sd122, 8'sd123, 8'sd124, 8'sd125, 8'sd126, 8'sd127,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0
    };

    always_comb begin
        data_out = en ? SILU_LUT[data_in[7:0]] : data_in;
    end
endmodule
