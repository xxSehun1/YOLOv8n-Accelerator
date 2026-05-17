`include "define.svh"
// ConfigLoader: one-shot Eyeriss scan-chain / PE-enable loader.
//
// The GIN/GON multicast IDs (XID/YID), the psum-chain map (LN_CONFIG) and the
// PE-enable mask (PE_EN) are purely geometric: the compiler emits them once in
// the [SHARED] section of mapping.txt because they are identical for every
// conv layer. ConfigLoader scans that data into the PE array a single time at
// NPU startup, then holds PE_en and asserts cfg_done so the PingPong_Ctrl may
// begin executing layers.
//
// Scan data source: a hex image ($readmemh) generated from mapping.txt
// [SHARED]; one XID/YID entry per PE (NUMS_PE_ROW*NUMS_PE_COL entries).
//
// FSM: IDLE -> SCAN_XID -> SCAN_YID -> SCAN_LN -> DONE.
module ConfigLoader #(
    parameter NUM_PE   = `NUMS_PE_ROW * `NUMS_PE_COL,
    parameter SCAN_HEX = "shared_config.hex"        // from mapping.txt [SHARED]
)(
    input  logic clk,
    input  logic rst,
    input  logic start,                             // pulse: begin scan-in
    output logic cfg_done,                          // high after scan completes

    // Scan-chain drive to PE_array.
    output logic                   set_XID,
    output logic [`XID_BITS-1:0]    ifmap_XID_scan_in,
    output logic [`XID_BITS-1:0]    filter_XID_scan_in,
    output logic [`XID_BITS-1:0]    ipsum_XID_scan_in,
    output logic [`XID_BITS-1:0]    opsum_XID_scan_in,

    output logic                   set_YID,
    output logic [`YID_BITS-1:0]    ifmap_YID_scan_in,
    output logic [`YID_BITS-1:0]    filter_YID_scan_in,
    output logic [`YID_BITS-1:0]    ipsum_YID_scan_in,
    output logic [`YID_BITS-1:0]    opsum_YID_scan_in,

    output logic                   set_LN,
    output logic [`NUMS_PE_ROW-2:0] LN_config_in,

    // Static PE-enable mask to PE_array.
    output logic [NUM_PE-1:0]       PE_en
);
    // TODO: IDLE waits for start; SCAN_XID shifts NUM_PE XID entries with
    // set_XID high; SCAN_YID does the same for YID; SCAN_LN drives
    // LN_config_in with set_LN; latch PE_en; raise cfg_done in DONE. Scan
    // tables loaded from SCAN_HEX via $readmemh.
endmodule
