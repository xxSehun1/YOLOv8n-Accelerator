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
    // TODO: data_out = en ? silu_lut[data_in] : data_in; silu_lut is a
    // 256-entry int8 table loaded via $readmemh (see design note above).
endmodule
