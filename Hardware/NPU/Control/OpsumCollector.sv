`include "define.svh"
// OpsumCollector: opsum-stream to PSUM_acc adapter.
//
// PE_array (via the GON) emits the gathered output partial sums as a
// valid/ready stream on GLB_data_out. The 16 PSUM_acc lanes, however, use an
// init / accum_en / last protocol. OpsumCollector bridges the two:
//   - drives GLB_opsum_ready back to the PE array
//   - routes each opsum word to the PSUM lane named by lane_sel
//   - turns pixel_init / pixel_last into per-lane init / last pulses
//   - holds the per-layer INT32 bias table (loaded from Weight_Buffer) and
//     presents it on psum_bias so PSUM_acc can seed the accumulator
//   - drains completed PSUM_acc lanes one at a time through the single shared
//     PPU (a combinational datapath with no handshake of its own)
//   - packs four int8 PPU results into one 32-bit activation word and streams
//     it to the IOMap_Buffer with a valid/ready handshake
//
// FSM: IDLE -> BIAS_LOAD -> COLLECT -> DRAIN.
module OpsumCollector #(
    parameter LANES = `NUMS_PE_COL
)(
    input  logic clk,
    input  logic rst,

    // Control from PingPong_Ctrl.
    input  logic         layer_start,    // pulse: begin a new conv layer
    input  logic         bias_en,        // layer carries an INT32 bias
    input  logic         pixel_init,     // start a new output-pixel reduction
    input  logic         pixel_last,     // current PE pass is the final partial
    input  logic [3:0]   lane_sel,       // PSUM lane for the next opsum word

    // Bias stream from Weight_Buffer.
    input  logic         bias_valid,
    input  logic signed [`PSUM_BITS-1:0] bias_word,
    output logic         bias_ready,

    // Opsum stream from PE_array (GON).
    input  logic         opsum_valid,
    input  logic signed [`PSUM_BITS-1:0] opsum_data,
    output logic         opsum_ready,

    // To PSUM_acc x16.
    output logic signed [`PSUM_BITS-1:0]       psum_data,    // broadcast word
    output logic [LANES*`PSUM_BITS-1:0]        psum_bias,    // packed 16 x int32
    output logic [LANES-1:0]                   psum_init,
    output logic [LANES-1:0]                   psum_accum_en,
    output logic [LANES-1:0]                   psum_last,
    input  logic [LANES-1:0]                   psum_complete,

    // To / from PPU (single shared PPU, combinational, no handshake).
    output logic [`DATA_BITS-1:0] ppu_data_in,    // biased psum -> PPU.data_in
    input  logic [7:0]            ppu_data_out,   // PPU.data_out (uint8)

    // Packed activation stream to IOMap_Buffer.
    output logic [`DATA_BITS-1:0] act_data,       // 4 x int8 packed word
    output logic                  act_valid,
    input  logic                  act_ready
);
    // TODO: BIAS_LOAD pulls LANES words off bias_* into psum_bias; COLLECT
    // routes opsum_data -> psum_data with per-lane init/accum_en/last decoded
    // from pixel_init/pixel_last/lane_sel; DRAIN walks psum_complete lanes
    // through the PPU (drive ppu_data_in, read ppu_data_out), packs four int8
    // results into act_data and streams it with act_valid/act_ready. When
    // bias_en is low psum_bias is held at zero.
endmodule
