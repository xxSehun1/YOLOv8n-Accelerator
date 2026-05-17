`include "define.svh"
// IOMap_Buffer: 64 KiB ping-pong activation buffer (instantiate x2).
//
// FSM: INPUT_READ <-> OUTPUT_WRITE. The two instances swap each layer, so
// layer N's output buffer becomes layer N+1's input buffer.
//   INPUT_READ:   streams the input feature map from SRAM towards the
//                 Line Buffer / PE array.
//   OUTPUT_WRITE: receives PPU results and writes them back to SRAM.
module IOMap_Buffer #(
    parameter DEPTH = (64*1024) / (`DATA_BITS/8)
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         mode_write,             // 0 = INPUT_READ, 1 = OUTPUT_WRITE
    input  logic         start,
    input  logic [`SRAM_ADDR_BITS-1:0] base_addr,// fmap base in SRAM
    input  logic [31:0]  length,                 // fmap size in bytes
    output logic         done,

    // SRAM port (read in INPUT mode, write in OUTPUT mode).
    output logic         sram_en,
    output logic         sram_we,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    output logic [`DATA_BITS-1:0]      sram_wdata,
    input  logic [`DATA_BITS-1:0]      sram_rdata,

    // Stream towards Line Buffer / PE (INPUT mode).
    output logic [`DATA_BITS-1:0] ifmap_data,
    output logic         ifmap_valid,
    input  logic         ifmap_ready,

    // Result stream from OpsumCollector (OUTPUT mode).
    input  logic [`DATA_BITS-1:0] ppu_data,
    input  logic         ppu_valid,
    output logic         ppu_ready
);
    // TODO: INPUT_READ streams SRAM -> ifmap_*; OUTPUT_WRITE drains ppu_* into
    // SRAM.
endmodule
