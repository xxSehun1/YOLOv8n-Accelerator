`include "define.svh"
// Line_Buffer: sliding-window row store for the conv.
//
// FSM: WARM_UP -> READY -> SHIFTING. Holds KERNEL rows of the input feature
// map and presents the KERNEL x KERNEL window to the PE array; flushed at the
// end of each tile. A 1x1 conv runs as a zero-padded 3x3, so KERNEL is always
// 3 here.
module Line_Buffer #(
    parameter MAX_WIDTH = 640
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         flush,                  // clear at tile boundary
    input  logic [15:0]  row_width,              // IN_W
    input  logic [3:0]   kernel,                 // 1 or 3 (effective)

    // Input stream from IOMap_Buffer.
    input  logic [`DATA_BITS-1:0] ifmap_data,
    input  logic         ifmap_valid,
    output logic         ifmap_ready,

    // Windowed output to the PE array.
    output logic [`DATA_BITS-1:0] win_data,
    output logic         win_valid,
    input  logic         win_ready
);
    // TODO: ring of KERNEL row buffers; WARM_UP fills the first rows, then
    // READY/SHIFTING emit the sliding window.
endmodule
