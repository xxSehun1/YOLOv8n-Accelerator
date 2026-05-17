`include "define.svh"
// PingPong_Ctrl: compute controller (top-level core FSM).
//
// FSM: IDLE -> PRELOAD -> STEADY -> SWAP -> DRAIN.
//
// On exec_valid it runs one CONV / POOL / ADD:
//   - tells Weight_Buffer to prefetch weights from SRAM
//   - tells the input IOMap_Buffer to stream the input feature map
//   - drives the Line_Buffer sliding window and the PE array
//   - collects PSUM, runs the PPU (requant + activation, or Add_Qint8)
//   - tells the output IOMap_Buffer to write results back to SRAM
// Pulses exec_done when the operation completes.
//
// Data paths (buffer <-> PE array <-> PPU) are wired in NPU_top; this module
// issues the control / handshake signals and sequences the FSM.
module PingPong_Ctrl (
    input  logic         clk,
    input  logic         rst,

    // From Decoder.
    input  logic         exec_valid,
    input  logic [1:0]   exec_op,                // 0 CONV / 1 POOL / 2 ADD
    input  logic [15:0]  exec_in_h, exec_in_w, exec_in_c, exec_out_c,
    input  logic [31:0]  exec_in_addr, exec_wgt_addr, exec_out_addr,
    input  logic [11:0]  exec_flags,
    input  logic [3:0]   exec_stride, exec_pad, exec_kernel,
    input  logic [9:0]   exec_pconfig,           // PE_CONFIG (p/strip/q)
    input  logic [5:0]   exec_shift, exec_lhs_shift, exec_rhs_shift,
    output logic         exec_done,

    // Weight_Buffer control (x2, sel picks the ping-pong half).
    output logic         wb_fill_start,
    output logic [`SRAM_ADDR_BITS-1:0] wb_fill_addr,
    output logic [31:0]  wb_fill_bytes,
    input  logic         wb_fill_done,
    output logic         wb_sel,

    // IOMap_Buffer control (x2).
    output logic         iob_in_start,  output logic [`SRAM_ADDR_BITS-1:0] iob_in_addr,
    output logic [31:0]  iob_in_len,    input  logic iob_in_done,
    output logic         iob_out_start, output logic [`SRAM_ADDR_BITS-1:0] iob_out_addr,
    output logic [31:0]  iob_out_len,   input  logic iob_out_done,
    output logic         iob_swap,

    // Line_Buffer control.
    output logic         lb_flush,
    output logic [15:0]  lb_row_width,
    output logic [3:0]   lb_kernel,

    // From ConfigLoader.
    input  logic         cfg_done,               // scan chains loaded; gates 1st EXEC

    // PE array control (per-layer config + per-transfer GIN/GON tags).
    // PE_en and the XID/YID/LN scan chains are geometric and driven by
    // ConfigLoader once at startup; this controller drives only the per-layer
    // PE_config and the per-transfer multicast tags.
    output logic [`CONFIG_SIZE-1:0] pe_config,    // {p,strip,q} from exec_pconfig
    output logic [1:0]   glb_sel,                 // GLB_data_in src: 0 ifmap 1 filter 2 ipsum
    output logic [`XID_BITS-1:0] ifmap_tag_X, filter_tag_X, ipsum_tag_X, opsum_tag_X,
    output logic [`YID_BITS-1:0] ifmap_tag_Y, filter_tag_Y, ipsum_tag_Y, opsum_tag_Y,
    // The valid/ready/data handshake runs directly between the buffers and
    // PE_array (wired in NPU_top); this controller only observes the ready
    // lines to pace tag advancement and stream sequencing.
    input  logic         glb_ifmap_ready,
    input  logic         glb_filter_ready,
    input  logic         glb_ipsum_ready,
    input  logic         glb_opsum_valid,

    // PPU control. Bias is folded into the PSUM_acc seed (see OpsumCollector),
    // so there is no ppu_bias_en; YOLOv8n uses SiLU, so there is no
    // ppu_relu_en.
    output logic [5:0]   ppu_shift,
    output logic         ppu_silu_en,
    output logic         ppu_maxpool_en,
    output logic         ppu_maxpool_init,

    // OpsumCollector control.
    output logic         oc_layer_start,         // pulse: new conv layer
    output logic         oc_bias_en,             // layer carries INT32 bias
    output logic         oc_pixel_init,          // start a new output-pixel reduction
    output logic         oc_pixel_last,          // final partial of the reduction
    output logic [3:0]   oc_lane_sel,            // target PSUM lane

    // Add_Qint8 control (residual path).
    output logic         add_en,
    output logic [5:0]   add_lhs_shift,
    output logic [5:0]   add_rhs_shift
);
    // TODO: IDLE/PRELOAD/STEADY/SWAP/DRAIN FSM; sequence the buffers, PE
    // array, PSUM and PPU per exec_op; pulse exec_done at the end.
endmodule
