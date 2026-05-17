`include "define.svh"
// Weight_Buffer: 64 KiB ping-pong weight buffer (instantiate x2).
//
// FSM: EMPTY -> FILLING -> FULL -> READING. Prefetches the next layer's
// weights from SRAM while the current layer computes; feeds filter words to
// the PE array.
module Weight_Buffer #(
    parameter DEPTH = (64*1024) / (`DATA_BITS/8)     // 64 KiB / 4 B
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         fill_start,             // begin refill from SRAM
    input  logic [`SRAM_ADDR_BITS-1:0] fill_addr,// weight staging addr in SRAM
    input  logic [31:0]  fill_bytes,             // weight blob size
    output logic         fill_done,              // refill complete

    // SRAM read port (to fill).
    output logic         sram_en,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    input  logic [`DATA_BITS-1:0]      sram_rdata,

    // PE-array filter feed.
    output logic [`DATA_BITS-1:0] filter_data,
    output logic         filter_valid,
    input  logic         filter_ready
);
    // TODO: fill phase reads SRAM into local memory; read phase streams filter
    // words to the PE array with a valid/ready handshake.
endmodule
