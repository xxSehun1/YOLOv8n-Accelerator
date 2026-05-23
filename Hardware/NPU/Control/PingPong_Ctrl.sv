`include "define.svh"
// PingPong_Ctrl: compute controller (top-level core FSM).
//
// MVP scope:
//   - CONV only (POOL/ADD raise exec_done immediately, deferred to v2)
//   - bias / SiLU / stride / pad assumed off; the first integration target is
//     a 1x1 conv with no bias, no SiLU, stride 1, pad 0
//   - Single tile (no spatial tiling)
//   - Linear walk: for each output pixel (oh, ow), reduce over IN_C/4
//     packed-channel groups
//
// FSM:
//   IDLE         wait for exec_valid and cfg_done
//   LOAD_WGT     pulse wb_fill_start; wait for wb_fill_done
//   LOAD_IF      start input IOMap_Buffer; flush Line_Buffer
//   RUN          drive PE array per output pixel:
//                  - first ic group: pulse oc_pixel_init
//                  - last  ic group: pulse oc_pixel_last
//                  - lane_sel walks 0..LANES-1 across output channels
//   START_OUT    start output IOMap_Buffer (write mode)
//   DRAIN        wait for OpsumCollector and output IOMap_Buffer to finish
//   DONE         pulse exec_done one cycle, swap ping-pong, return to IDLE
//
// The inner data-delivery (per-cycle tags, GLB stream pacing) is left as
// TODO: the MVP wires the high-level signals so integration can begin; the
// actual per-cycle protocol will be filled in once the integration testbench
// exposes the exact handshake timing.
module PingPong_Ctrl (
    input  logic         clk,
    input  logic         rst,

    // From Decoder.
    input  logic         exec_valid,
    input  logic [1:0]   exec_op,
    input  logic [15:0]  exec_in_h, exec_in_w, exec_in_c, exec_out_c,
    input  logic [31:0]  exec_in_addr, exec_wgt_addr, exec_out_addr,
    input  logic [11:0]  exec_flags,
    input  logic [3:0]   exec_stride, exec_pad, exec_kernel,
    input  logic [9:0]   exec_pconfig,
    input  logic [5:0]   exec_shift, exec_lhs_shift, exec_rhs_shift,
    output logic         exec_done,

    // Weight_Buffer control (x2).
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
    input  logic         cfg_done,

    // PE array control.
    output logic [`CONFIG_SIZE-1:0] pe_config,
    output logic [1:0]   glb_sel,
    output logic [`XID_BITS-1:0] ifmap_tag_X, filter_tag_X, ipsum_tag_X, opsum_tag_X,
    output logic [`YID_BITS-1:0] ifmap_tag_Y, filter_tag_Y, ipsum_tag_Y, opsum_tag_Y,
    input  logic         glb_ifmap_ready,
    input  logic         glb_filter_ready,
    input  logic         glb_ipsum_ready,
    input  logic         glb_opsum_valid,

    // PPU control.
    output logic [5:0]   ppu_shift,
    output logic         ppu_silu_en,
    output logic         ppu_maxpool_en,
    output logic         ppu_maxpool_init,

    // OpsumCollector control.
    output logic         oc_layer_start,
    output logic         oc_bias_en,
    output logic         oc_pixel_init,
    output logic         oc_pixel_last,
    output logic [3:0]   oc_lane_sel,

    // Add_Qint8 control (residual path, MVP unused).
    output logic         add_en,
    output logic [5:0]   add_lhs_shift,
    output logic [5:0]   add_rhs_shift
);
    // Local decode of FLAGS.
    logic flag_silu, flag_bias;
    assign flag_silu = exec_flags[0] & exec_flags[1];
    assign flag_bias = exec_flags[3];

    // FSM.
    typedef enum logic [3:0] {
        S_IDLE, S_LOAD_WGT, S_LOAD_IF, S_RUN, S_START_OUT, S_DRAIN, S_DONE
    } state_t;
    state_t state, next;

    // Latched layer parameters (captured at IDLE->LOAD_WGT).
    logic [15:0] in_h, in_w, in_c, out_c;
    logic [31:0] in_addr, wgt_addr, out_addr;
    logic [5:0]  shift;
    logic [9:0]  pconfig;
    logic        sel;                  // ping-pong half (toggles per layer)

    // Output-pixel walker (RUN phase).
    logic [15:0] oh, ow;               // current output pixel
    logic [15:0] ic_grp;               // current input-channel group (4 channels per word)
    logic [15:0] ic_grp_max;           // (in_c + 3) / 4
    logic [15:0] out_grp;              // current output-channel group within m

    // 1x1 / no stride/pad MVP: output dims = input dims (H,W match for 1x1).
    // For other kernels the controller would compute (in - K + 2P)/U + 1.
    logic [15:0] out_h, out_w;
    assign out_h = in_h;
    assign out_w = in_w;

    // Next-state.
    always_comb begin
        next = state;
        case (state)
            S_IDLE:      if (exec_valid && cfg_done) next = (exec_op == 2'd0) ? S_LOAD_WGT : S_DONE;
            S_LOAD_WGT:  if (wb_fill_done)           next = S_LOAD_IF;
            S_LOAD_IF:                                next = S_RUN;
            S_RUN:       if (oh == out_h - 1 && ow == out_w - 1 &&
                             ic_grp == ic_grp_max - 1)
                                                     next = S_START_OUT;
            S_START_OUT:                              next = S_DRAIN;
            S_DRAIN:     if (iob_out_done)           next = S_DONE;
            S_DONE:                                   next = S_IDLE;
            default:                                  next = S_IDLE;
        endcase
    end

    // Sequential.
    always_ff @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            in_h <= 0; in_w <= 0; in_c <= 0; out_c <= 0;
            in_addr <= 0; wgt_addr <= 0; out_addr <= 0;
            shift   <= 0; pconfig <= 0;
            sel     <= 0;
            oh <= 0; ow <= 0; ic_grp <= 0; out_grp <= 0;
            ic_grp_max <= 0;
        end else begin
            state <= next;

            case (state)
                S_IDLE: if (exec_valid && cfg_done && exec_op == 2'd0) begin
                    in_h     <= exec_in_h;
                    in_w     <= exec_in_w;
                    in_c     <= exec_in_c;
                    out_c    <= exec_out_c;
                    in_addr  <= exec_in_addr;
                    wgt_addr <= exec_wgt_addr;
                    out_addr <= exec_out_addr;
                    shift    <= exec_shift;
                    pconfig  <= exec_pconfig;
                    ic_grp_max <= (exec_in_c + 3) >> 2;        // ceil(IN_C/4)
                    oh <= 0; ow <= 0; ic_grp <= 0; out_grp <= 0;
                end

                S_RUN: begin
                    // Walk inner-most ic_grp, then ow, then oh.
                    if (ic_grp == ic_grp_max - 1) begin
                        ic_grp <= 0;
                        if (ow == out_w - 1) begin
                            ow <= 0;
                            if (oh != out_h - 1) oh <= oh + 1;
                        end else begin
                            ow <= ow + 1;
                        end
                    end else begin
                        ic_grp <= ic_grp + 1;
                    end
                end

                S_DONE: sel <= ~sel;                            // ping-pong swap

                default: ;
            endcase
        end
    end

    // Outputs.

    // Weight_Buffer: pulse fill_start at IDLE->LOAD_WGT entry.
    assign wb_fill_start = (state == S_IDLE) && (next == S_LOAD_WGT);
    assign wb_fill_addr  = exec_wgt_addr[`SRAM_ADDR_BITS-1:0];
    // Weight blob size: OUT_C * IN_C * K * K  (+ OUT_C*4 if bias). MVP: no bias.
    assign wb_fill_bytes = exec_out_c * exec_in_c * exec_kernel * exec_kernel;
    assign wb_sel        = sel;

    // IOMap_Buffer: input mode loads at LOAD_IF; output mode starts at START_OUT.
    assign iob_in_start  = (state == S_LOAD_IF);
    assign iob_in_addr   = in_addr[`SRAM_ADDR_BITS-1:0];
    assign iob_in_len    = in_c * in_h * in_w;                  // bytes (int8)
    assign iob_out_start = (state == S_START_OUT);
    assign iob_out_addr  = out_addr[`SRAM_ADDR_BITS-1:0];
    assign iob_out_len   = out_c * out_h * out_w;
    assign iob_swap      = (state == S_DONE);

    // Line_Buffer: flush on layer start; row_width = IN_W; kernel = exec_kernel.
    assign lb_flush     = (state == S_LOAD_IF);
    assign lb_row_width = in_w;
    assign lb_kernel    = exec_kernel;

    // PE_array per-layer config.
    assign pe_config = {22'd0, pconfig};

    // GIN/GON multicast tags. The MVP cycles a simple (ow, oh) tagging.

    assign ifmap_tag_X  = ow[`XID_BITS-1:0];
    assign ifmap_tag_Y  = oh[`YID_BITS-1:0];
    assign filter_tag_X = ic_grp[`XID_BITS-1:0];
    assign filter_tag_Y = out_grp[`YID_BITS-1:0];
    assign ipsum_tag_X  = ow[`XID_BITS-1:0];
    assign ipsum_tag_Y  = oh[`YID_BITS-1:0];
    assign opsum_tag_X  = ow[`XID_BITS-1:0];
    assign opsum_tag_Y  = oh[`YID_BITS-1:0];

    // GLB source select. MVP just stays on ifmap; per-phase muxing TODO.
    assign glb_sel = 2'd0;

    // PPU control: shift from CONFIG; SiLU/maxpool off in MVP.
    assign ppu_shift        = shift;
    assign ppu_silu_en      = 1'b0;            // MVP: SiLU stubbed
    assign ppu_maxpool_en   = 1'b0;
    assign ppu_maxpool_init = 1'b0;

    // OpsumCollector control.
    assign oc_layer_start = (state == S_LOAD_IF);
    assign oc_bias_en     = 1'b0;              // MVP: no bias
    assign oc_pixel_init  = (state == S_RUN) && (ic_grp == 0);
    assign oc_pixel_last  = (state == S_RUN) && (ic_grp == ic_grp_max - 1);
    assign oc_lane_sel    = out_grp[3:0];

    // Add_Qint8 (residual): unused in MVP.
    assign add_en        = 1'b0;
    assign add_lhs_shift = exec_lhs_shift;
    assign add_rhs_shift = exec_rhs_shift;

    // exec_done: pulse one cycle in S_DONE.
    assign exec_done = (state == S_DONE);

endmodule
