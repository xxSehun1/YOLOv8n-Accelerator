`include "define.svh"
// PingPong_Ctrl v3: full Eyeriss row-stationary scheduler.
//
// Ports the nested-loop sequencer from lab-3/testbench/tb_array.cpp into
// hardware. The MVP test layer (hardcoded) is a 3x3 conv on a 4x4 input:
//
//   IN_H = IN_W = 4, IN_C = 4, OUT_C = 4, K = 3, stride = 1, pad = 0
//   -> OUT_H = OUT_W = 2  (8 output values per channel = 16 total)
//
// Mapping parameters (matches a workable schedule for the 16x16 array):
//   e = 2 (output rows per pass)         p = 1 (output channels per PE col)
//   q = 4 (input channels per word)      r = 1 (channel-fold passes)
//   t = 4 (output-channel passes, M/p)   t_H = t_W = 1 (single tile)
//   FILT_ROW = FILT_COL = 3
//   IFMAP_COL = 4, OFMAP_COL = 2
//
// FSM:
//   IDLE -> LOAD_WGT -> PE_CONFIG -> FILTER
//   -> IFMAP -> IPSUM -> OPSUM  (loop OFMAP_COL times)
//   -> START_OUT -> DRAIN -> DONE
//
// Within each phase, the nested counter logic mirrors lab-3 line-by-line.
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

    // Weight_Buffer.
    output logic         wb_fill_start,
    output logic [`SRAM_ADDR_BITS-1:0] wb_fill_addr,
    output logic [31:0]  wb_fill_bytes,
    input  logic         wb_fill_done,
    output logic         wb_sel,

    // IOMap_Buffer.
    output logic         iob_in_start,  output logic [`SRAM_ADDR_BITS-1:0] iob_in_addr,
    output logic [31:0]  iob_in_len,    input  logic iob_in_done,
    output logic         iob_out_start, output logic [`SRAM_ADDR_BITS-1:0] iob_out_addr,
    output logic [31:0]  iob_out_len,   input  logic iob_out_done,
    output logic         iob_swap,

    // Line_Buffer (legacy).
    output logic         lb_flush,
    output logic [15:0]  lb_row_width,
    output logic [3:0]   lb_kernel,

    // From ConfigLoader.
    input  logic         cfg_done,

    // PE array.
    output logic [`CONFIG_SIZE-1:0] pe_config,
    output logic [1:0]   glb_sel,
    output logic [`XID_BITS-1:0] ifmap_tag_X, filter_tag_X, ipsum_tag_X, opsum_tag_X,
    output logic [`YID_BITS-1:0] ifmap_tag_Y, filter_tag_Y, ipsum_tag_Y, opsum_tag_Y,
    input  logic         glb_ifmap_ready,
    input  logic         glb_ifmap_valid,            // lb_win_valid gated by phase
    input  logic         glb_filter_ready,
    input  logic         glb_filter_valid,           // wb_filter_valid
    input  logic         glb_ipsum_ready,
    input  logic         glb_opsum_valid,
    input  logic         glb_opsum_ready,           // observe (driven by OpsumCollector)
    output logic         pp_ipsum_valid,
    output logic         ifmap_en,                   // high only in S_IFMAP; gates lb_win_valid

    // PPU.
    output logic [5:0]   ppu_shift,
    output logic         ppu_silu_en,
    output logic         ppu_maxpool_en,
    output logic         ppu_maxpool_init,

    // OpsumCollector.
    output logic         oc_layer_start,
    output logic         oc_bias_en,
    output logic         oc_pixel_init,
    output logic         oc_pixel_last,
    output logic         oc_layer_last,  // HIGH only on the final opsum_accept of the layer
    output logic [3:0]   oc_lane_sel,

    // Add_Qint8.
    output logic         add_en,
    output logic [5:0]   add_lhs_shift,
    output logic [5:0]   add_rhs_shift
);
    // Hardcoded mapping parameters for the v3 test layer.
    localparam int E         = 2;
    localparam int P         = 1;
    localparam int Q         = 4;
    localparam int R         = 1;
    localparam int T         = 4;
    localparam int T_H       = 1;
    localparam int T_W       = 1;
    localparam int F_ROW     = 3;
    localparam int F_COL     = 3;
    localparam int IFMAP_COL = 4;
    localparam int OFMAP_COL = 2;
    localparam int P_T       = P * T;          // 4

    // FSM state.
    typedef enum logic [3:0] {
        S_IDLE       = 4'd0,
        S_LOAD_WGT   = 4'd1,
        S_PE_CONFIG  = 4'd2,
        S_FILTER     = 4'd3,
        S_IFMAP      = 4'd4,
        S_IPSUM      = 4'd5,
        S_OPSUM      = 4'd6,
        S_START_OUT  = 4'd7,
        S_DRAIN      = 4'd8,
        S_DONE       = 4'd9
    } state_t;
    state_t state, next;

    // Latched layer parameters.
    logic [15:0] in_h, in_w, in_c, out_c;
    logic [31:0] in_addr, wgt_addr, out_addr;
    logic [5:0]  shift;
    logic [9:0]  pconfig;
    logic        sel;

    // Counters (mirrors lab-3 tb_array.cpp Index struct).
    logic [3:0] cnt_r, cnt_tH, cnt_tW;
    logic [3:0] cnt_f_ch, cnt_f_col, cnt_f_row, cnt_f_num;
    logic [3:0] cnt_i_ch, cnt_i_row;
    logic [4:0] cnt_i_col;                       // up to IFMAP_COL
    logic [3:0] cnt_p_ch, cnt_p_row, cnt_p_col;
    logic [3:0] cnt_o_ch, cnt_o_row, cnt_o_col;

    // Per-phase end flags (set when phase finishes, cleared on phase entry).
    logic filter_done_int, ifmap_done_int, ipsum_done_int, opsum_done_int;
    logic opsum_all_done;                        // set when last ofmap_col done

    // Handshake accept pulses.
    // Both valid AND ready must be true so counters only advance when the
    // GIN is actually transferring a word.  Without the valid check the
    // counter can race ahead while the source buffer isn't yet driving data,
    // causing PEs to stay in WEIGHT while PingPong thinks the filter phase
    // is done (→ GLB_ifmap_ready stuck low → S_IFMAP never exits).
    logic filter_accept, ifmap_accept, ipsum_accept, opsum_accept;
    assign filter_accept = (state == S_FILTER) && glb_filter_valid && glb_filter_ready;
    assign ifmap_accept  = (state == S_IFMAP)  && glb_ifmap_valid  && glb_ifmap_ready;
    assign ipsum_accept  = (state == S_IPSUM)  && glb_ipsum_ready;
    assign opsum_accept  = (state == S_OPSUM)  && glb_opsum_valid && glb_opsum_ready;

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_IDLE:      if (exec_valid && cfg_done)
                             next = (exec_op == 2'd0) ? S_LOAD_WGT : S_DONE;
            S_LOAD_WGT:  if (wb_fill_done)         next = S_PE_CONFIG;
            S_PE_CONFIG:                             next = S_FILTER;
            S_FILTER:    if (filter_done_int)      next = S_IFMAP;
            S_IFMAP:     if (ifmap_done_int)       next = S_IPSUM;
            S_IPSUM:     if (ipsum_done_int)       next = S_OPSUM;
            S_OPSUM:     if (opsum_done_int)
                             next = opsum_all_done ? S_START_OUT : S_IFMAP;
            S_START_OUT:                             next = S_DRAIN;
            S_DRAIN:                                 next = S_DONE;
            S_DONE:                                  next = S_IDLE;
            default:                                 next = S_IDLE;
        endcase
    end

    // Sequential logic.
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            in_h <= 0; in_w <= 0; in_c <= 0; out_c <= 0;
            in_addr <= 0; wgt_addr <= 0; out_addr <= 0;
            shift   <= 0; pconfig <= 0;
            sel     <= 0;
            cnt_r <= 0; cnt_tH <= 0; cnt_tW <= 0;
            cnt_f_ch <= 0; cnt_f_col <= 0; cnt_f_row <= 0; cnt_f_num <= 0;
            cnt_i_ch <= 0; cnt_i_row <= 0; cnt_i_col <= 0;
            cnt_p_ch <= 0; cnt_p_row <= 0; cnt_p_col <= 0;
            cnt_o_ch <= 0; cnt_o_row <= 0; cnt_o_col <= 0;
            filter_done_int <= 0;
            ifmap_done_int  <= 0;
            ipsum_done_int  <= 0;
            opsum_done_int  <= 0;
            opsum_all_done  <= 0;
        end else begin
            state <= next;

            // Latch layer params on IDLE -> LOAD_WGT.
            if (state == S_IDLE && exec_valid && cfg_done && exec_op == 2'd0) begin
                in_h     <= exec_in_h;
                in_w     <= exec_in_w;
                in_c     <= exec_in_c;
                out_c    <= exec_out_c;
                in_addr  <= exec_in_addr;
                wgt_addr <= exec_wgt_addr;
                out_addr <= exec_out_addr;
                shift    <= exec_shift;
                pconfig  <= exec_pconfig;
            end

            // Clear end-flags on phase entry.
            if (state != next) begin
                case (next)
                    S_FILTER: filter_done_int <= 1'b0;
                    S_IFMAP:  ifmap_done_int  <= 1'b0;
                    S_IPSUM:  ipsum_done_int  <= 1'b0;
                    S_OPSUM:  opsum_done_int  <= 1'b0;
                    default: ;
                endcase
            end

            // Filter counter (mirrors lab-3 send_filter).
            if (filter_accept) begin
                if (cnt_f_ch == Q*(R-1)) begin
                    cnt_f_ch <= 0;
                    if (cnt_f_col == F_COL-1) begin
                        cnt_f_col <= 0;
                        if (cnt_f_row == F_ROW-1) begin
                            cnt_f_row <= 0;
                            // count_t (lab-3: when filter_num % p == p-1)
                            if (cnt_f_num % P == P-1) begin
                                if (cnt_tH == T_H-1) begin
                                    cnt_tH <= 0;
                                    if (cnt_tW == T_W-1) cnt_tW <= 0;
                                    else                  cnt_tW <= cnt_tW + 1;
                                end else cnt_tH <= cnt_tH + 1;
                            end
                            if (cnt_f_num == P_T-1) begin
                                cnt_f_num       <= 0;
                                filter_done_int <= 1'b1;
                            end else cnt_f_num <= cnt_f_num + 1;
                        end else cnt_f_row <= cnt_f_row + 1;
                    end else cnt_f_col <= cnt_f_col + 1;
                end else cnt_f_ch <= cnt_f_ch + Q;

                if (cnt_r == R-1) cnt_r <= 0;
                else              cnt_r <= cnt_r + 1;
            end

            // Ifmap counter (mirrors lab-3 send_ifmap).
            if (ifmap_accept) begin
                if (cnt_i_ch == Q*(R-1)) begin
                    cnt_i_ch <= 0;
                    if (cnt_i_row == E + F_ROW - 2) begin
                        cnt_i_row <= 0;
                        if (cnt_i_col >= F_COL - 1) begin
                            ifmap_done_int <= 1'b1;
                            if (cnt_i_col == IFMAP_COL-1) cnt_i_col <= 0;
                            else                          cnt_i_col <= cnt_i_col + 1;
                        end else cnt_i_col <= cnt_i_col + 1;
                    end else cnt_i_row <= cnt_i_row + 1;
                end else cnt_i_ch <= cnt_i_ch + Q;

                if (cnt_r == R-1) cnt_r <= 0;
                else              cnt_r <= cnt_r + 1;
            end

            // Ipsum counter (mirrors lab-3 send_ipsum).
            if (ipsum_accept) begin
                if (cnt_p_ch % P == P-1) begin
                    if (cnt_tH == T_H-1) begin
                        cnt_tH <= 0;
                        if (cnt_tW == T_W-1) cnt_tW <= 0;
                        else                  cnt_tW <= cnt_tW + 1;
                    end else cnt_tH <= cnt_tH + 1;
                end
                if (cnt_p_ch == P_T-1) begin
                    cnt_p_ch <= 0;
                    if (cnt_p_row == E-1) begin
                        cnt_p_row      <= 0;
                        ipsum_done_int <= 1'b1;
                        if (cnt_p_col == OFMAP_COL-1) cnt_p_col <= 0;
                        else                          cnt_p_col <= cnt_p_col + 1;
                    end else cnt_p_row <= cnt_p_row + 1;
                end else cnt_p_ch <= cnt_p_ch + 1;
            end

            // Opsum counter (mirrors lab-3 store_data).
            if (opsum_accept) begin
                if (cnt_o_ch % P == P-1) begin
                    if (cnt_tH == T_H-1) begin
                        cnt_tH <= 0;
                        if (cnt_tW == T_W-1) cnt_tW <= 0;
                        else                  cnt_tW <= cnt_tW + 1;
                    end else cnt_tH <= cnt_tH + 1;
                end
                if (cnt_o_ch == P_T-1) begin
                    cnt_o_ch <= 0;
                    if (cnt_o_row == E-1) begin
                        cnt_o_row      <= 0;
                        opsum_done_int <= 1'b1;
                        if (cnt_o_col == OFMAP_COL-1) begin
                            cnt_o_col      <= 0;
                            opsum_all_done <= 1'b1;
                        end else cnt_o_col <= cnt_o_col + 1;
                    end else cnt_o_row <= cnt_o_row + 1;
                end else cnt_o_ch <= cnt_o_ch + 1;
            end

            // Ping-pong swap on DONE.
            if (state == S_DONE) sel <= ~sel;
        end
    end

    // Outputs.

    // Weight_Buffer: fill on entry to LOAD_WGT.
    assign wb_fill_start = (state == S_IDLE) && (next == S_LOAD_WGT);
    assign wb_fill_addr  = exec_wgt_addr[`SRAM_ADDR_BITS-1:0];
    assign wb_fill_bytes = F_ROW * F_COL * Q * R * P_T * T_H * T_W * 4;   // bytes
    assign wb_sel        = sel;

    // IOMap_Buffer.
    assign iob_in_start  = (state == S_PE_CONFIG);
    assign iob_in_addr   = in_addr[`SRAM_ADDR_BITS-1:0];
    assign iob_in_len    = in_c * in_h * in_w;
    assign iob_out_start = (state == S_START_OUT);
    assign iob_out_addr  = out_addr[`SRAM_ADDR_BITS-1:0];
    assign iob_out_len   = OFMAP_COL * E * P_T;     // bytes (1 byte per output)
    assign iob_swap      = (state == S_DONE);

    // Line_Buffer (legacy).
    assign lb_flush     = (state == S_PE_CONFIG);
    assign lb_row_width = in_w;
    assign lb_kernel    = exec_kernel;

    // PE config.
    assign pe_config = {22'd0, pconfig};

    // GLB select per phase.
    always_comb begin
        case (state)
            S_FILTER: glb_sel = 2'd1;
            S_IFMAP:  glb_sel = 2'd0;
            S_IPSUM:  glb_sel = 2'd2;
            default:  glb_sel = 2'd0;
        endcase
    end

    // Tag generation (mirrors lab-3 tb_array.cpp formulas).
    assign filter_tag_X = cnt_f_row + F_ROW * cnt_tW;
    assign filter_tag_Y = cnt_r + cnt_tH;
    assign ifmap_tag_X  = cnt_i_row;
    assign ifmap_tag_Y  = cnt_r;
    assign ipsum_tag_X  = cnt_p_row + E * cnt_tW;
    assign ipsum_tag_Y  = cnt_tH;
    assign opsum_tag_X  = cnt_o_row + E * cnt_tW;
    assign opsum_tag_Y  = cnt_tH;

    // Ipsum: PingPong drives valid during S_IPSUM (zero seed).
    assign pp_ipsum_valid = (state == S_IPSUM);

    // ifmap_en: tells NPU_top when to forward lb_win_valid to the ifmap GIN.
    // Keeping it low outside S_IFMAP prevents PEs that just exited WEIGHT
    // from receiving ifmap words and advancing IF→COMPUTE before PingPong
    // officially enters S_IFMAP (lb_win_valid can arrive during S_FILTER).
    assign ifmap_en = (state == S_IFMAP);

    // PPU control.
    assign ppu_shift        = shift;
    assign ppu_silu_en      = 1'b0;
    assign ppu_maxpool_en   = 1'b0;
    assign ppu_maxpool_init = 1'b0;

    // OpsumCollector control.
    assign oc_layer_start = (state == S_PE_CONFIG);
    assign oc_bias_en     = 1'b0;
    // Each opsum is a complete output value: pulse both init and last together
    // so PSUM_acc loads psum_in directly and marks itself complete in one shot.
    assign oc_pixel_init  = opsum_accept;
    assign oc_pixel_last  = opsum_accept;
    assign oc_lane_sel    = cnt_o_ch[3:0];
    // oc_layer_last: asserted ONLY on the very last opsum_accept of the entire
    // layer (last channel of last output row of last output column).  Used by
    // OpsumCollector to set layer_last_seen so it knows when to stop collecting.
    // This is intentionally separate from oc_pixel_last: every word needs
    // pixel_last=1 to make PSUM_acc complete immediately (init+last together),
    // but only the final word should tell OC the layer is over.
    assign oc_layer_last  = opsum_accept
                            && (cnt_o_ch  == P_T       - 1)
                            && (cnt_o_row == E         - 1)
                            && (cnt_o_col == OFMAP_COL - 1);

    // Add_Qint8 (unused in v3 conv path).
    assign add_en        = 1'b0;
    assign add_lhs_shift = exec_lhs_shift;
    assign add_rhs_shift = exec_rhs_shift;

    assign exec_done = (state == S_DONE);

endmodule
