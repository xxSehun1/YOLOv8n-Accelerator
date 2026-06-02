`include "define.svh"

// PingPong_Ctrl
//
// ISA-driven scheduler for the true hardware dataflow.  This controller no
// longer assumes one fixed synthetic layer shape.  It latches the Decoder's
// CONFIG/EXEC fields and derives all transfer lengths from the instruction
// tensor geometry.
//
// Step-1 scope:
//   - start Weight_Buffer fill from SRAM;
//   - start IOMap input/output buffers;
//   - start Line_Buffer and drain its window stream under valid/ready
//     backpressure;
//   - drain filter/ipsum/opsum handshakes with bounded dynamic counters;
//   - expose PPU control flags including SiLU enable.
//
// Later PE-array scheduling can refine the tag policy, but the buffer/control
// handshake lengths are already instruction-driven and do not contain the old
// hardcoded E/P/Q/R/T/F_ROW/F_COL test geometry.
module PingPong_Ctrl (
    input  logic         clk,
    input  logic         rst,

    input  logic         exec_valid,
    input  logic [1:0]   exec_op,
    input  logic [15:0]  exec_in_h, exec_in_w, exec_in_c, exec_out_c,
    input  logic [31:0]  exec_in_addr, exec_wgt_addr, exec_out_addr,
    input  logic [11:0]  exec_flags,
    input  logic [3:0]   exec_stride, exec_pad, exec_kernel,
    input  logic [9:0]   exec_pconfig,
    input  logic [5:0]   exec_shift, exec_lhs_shift, exec_rhs_shift,
    output logic         exec_done,

    output logic         wb_fill_start,
    output logic [`SRAM_ADDR_BITS-1:0] wb_fill_addr,
    output logic [31:0]  wb_fill_bytes,
    input  logic         wb_fill_done,
    output logic         wb_sel,

    output logic         iob_in_start,  output logic [`SRAM_ADDR_BITS-1:0] iob_in_addr,
    output logic [31:0]  iob_in_len,    input  logic iob_in_done,
    output logic         iob_out_start, output logic [`SRAM_ADDR_BITS-1:0] iob_out_addr,
    output logic [31:0]  iob_out_len,   input  logic iob_out_done,
    output logic         iob_swap,

    output logic         lb_flush,
    output logic [15:0]  lb_row_width,
    output logic [3:0]   lb_kernel,
    output logic         pe_tile_start,

    input  logic         cfg_done,

    output logic [`CONFIG_SIZE-1:0] pe_config,
    output logic [1:0]   glb_sel,
    output logic [`XID_BITS-1:0] ifmap_tag_X, filter_tag_X, ipsum_tag_X, opsum_tag_X,
    output logic [`YID_BITS-1:0] ifmap_tag_Y, filter_tag_Y, ipsum_tag_Y, opsum_tag_Y,
    input  logic         glb_ifmap_ready,
    input  logic         glb_ifmap_valid,
    input  logic         glb_filter_ready,
    input  logic         glb_filter_valid,
    input  logic         glb_ipsum_ready,
    input  logic         glb_opsum_valid,
    input  logic         glb_opsum_ready,
    output logic         pp_ipsum_valid,
    output logic         ifmap_en,

    output logic [5:0]   ppu_shift,
    output logic         ppu_silu_en,
    output logic         ppu_maxpool_en,
    output logic         ppu_maxpool_init,

    output logic         oc_layer_start,
    output logic         oc_bias_en,
    output logic         oc_pixel_init,
    output logic         oc_pixel_last,
    output logic         oc_layer_last,
    output logic [3:0]   oc_lane_sel,
    output logic         oc_spatial_mode,
    output logic [15:0]  oc_spatial_cols,
    output logic [15:0]  oc_spatial_groups,
    output logic [4:0]   oc_spatial_channel,
    output logic         oc_spatial_tile_last,
    output logic         oc_spatial_last,
    input  logic         spatial_opsum_valid,
    input  logic         spatial_opsum_ready,

    output logic         add_en,
    output logic [5:0]   add_lhs_shift,
    output logic [5:0]   add_rhs_shift,

    input  logic         oc_done
);
    localparam logic [1:0] EXEC_CONV = 2'd0;
    localparam logic [1:0] EXEC_POOL = 2'd1;
    localparam logic [1:0] EXEC_ADD  = 2'd2;
    // True spatial tiling: PE columns represent output X positions inside the
    // current tile.  ifmap tag_Y selects kernel row; tag_X selects tile column.
    localparam logic [15:0] STRIP_MAX = `NUMS_PE_COL;

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

    logic [1:0]  op_l;
    logic [15:0] in_h, in_w, in_c, out_c;
    logic [15:0] out_h, out_w;
    logic [31:0] in_addr, wgt_addr, out_addr;
    logic [11:0] flags;
    logic [3:0]  stride, pad, kernel;
    logic [5:0]  shift, lhs_shift, rhs_shift;
    logic [9:0]  pconfig;
    logic        sel;

    logic [31:0] weight_bytes_l;
    logic [31:0] input_bytes_l;
    logic [31:0] output_bytes_l;
    logic [31:0] filter_words_total;
    logic [31:0] ifmap_words_total;
    logic [31:0] output_elems_total;
    logic [31:0] row_ifmap_words_total;
    logic [31:0] row_active_ifmap_words_total;
    logic [31:0] row_output_elems_total;
    logic [15:0] strip_ow_base;
    logic [15:0] strip_w;

    logic [31:0] filter_count;
    logic [31:0] ifmap_count;
    logic [31:0] ipsum_count;
    logic [31:0] opsum_count;
    logic [15:0] ifmap_oy;
    logic [15:0] ifmap_ow;
    logic [3:0]  ifmap_tap_y;
    logic [3:0]  ifmap_tap_x;
    logic [`XID_BITS-1:0] ifmap_diag_tag;
    logic [3:0]  ifmap_diag_rep;
    logic [3:0]  filter_kcol;
    logic [3:0]  filter_krow;
    logic [15:0] ipsum_ow;
    logic [15:0] ipsum_oc;
    logic [15:0] opsum_ow;
    logic [15:0] opsum_oc;

    logic filter_accept, ifmap_accept, ipsum_accept, opsum_accept;
    logic start_conv;
    logic start_pool;
    logic start_add;
    logic [15:0] ifmap_tag_x_wide;
    logic [`XID_BITS-1:0] ifmap_tag_x_calc;
    logic strip_done_after_opsum;

    assign filter_accept = (state == S_FILTER) && glb_filter_valid && glb_filter_ready;
    assign ifmap_accept  = (state == S_IFMAP)  && glb_ifmap_valid  && glb_ifmap_ready;
    assign ipsum_accept  = (state == S_IPSUM)  && glb_ipsum_ready;
    assign opsum_accept  = (state == S_OPSUM)
                          && ((op_l == EXEC_CONV)
                              ? (spatial_opsum_valid && spatial_opsum_ready)
                              : (glb_opsum_valid && glb_opsum_ready));

    assign start_conv = (state == S_IDLE) && exec_valid && cfg_done && (exec_op == EXEC_CONV);
    assign start_pool = (state == S_IDLE) && exec_valid && cfg_done && (exec_op == EXEC_POOL);
    assign start_add  = (state == S_IDLE) && exec_valid && cfg_done && (exec_op == EXEC_ADD);

    function automatic logic [31:0] align4(input logic [31:0] value);
        align4 = (value + 32'd3) & 32'hFFFF_FFFC;
    endfunction

    function automatic logic [31:0] ceil_words(input logic [31:0] nbytes);
        ceil_words = align4(nbytes) >> 2;
    endfunction

    function automatic logic [15:0] ceil4_groups(input logic [15:0] channels);
        ceil4_groups = (channels + 16'd3) >> 2;
    endfunction

    function automatic logic [15:0] norm_stride(input logic [3:0] s);
        norm_stride = (s == 4'd0) ? 16'd1 : {12'd0, s};
    endfunction

    function automatic logic [3:0] norm_kernel(input logic [3:0] k);
        norm_kernel = (k == 4'd0) ? 4'd1 : k;
    endfunction

    function automatic logic [15:0] calc_out_dim(
        input logic [15:0] in_dim,
        input logic [3:0]  pad_v,
        input logic [3:0]  kernel_v,
        input logic [3:0]  stride_v
    );
        logic [31:0] padded;
        logic [31:0] k32;
        logic [31:0] s32;
        begin
            padded = {16'd0, in_dim} + ({28'd0, pad_v} << 1);
            k32 = {28'd0, norm_kernel(kernel_v)};
            s32 = {16'd0, norm_stride(stride_v)};
            if (padded < k32) calc_out_dim = 16'd0;
            else              calc_out_dim = 16'(((padded - k32) / s32) + 32'd1);
        end
    endfunction

    function automatic logic [31:0] conv_weight_bytes(
        input logic [15:0] oc,
        input logic [15:0] ic,
        input logic [3:0]  k
    );
        conv_weight_bytes = {16'd0, oc} * {16'd0, ic}
                          * {28'd0, norm_kernel(k)} * {28'd0, norm_kernel(k)};
    endfunction

    function automatic logic [31:0] conv_param_bytes(
        input logic [15:0] oc,
        input logic [15:0] ic,
        input logic [3:0]  k,
        input logic        has_bias
    );
        conv_param_bytes = conv_weight_bytes(oc, ic, k)
                         + (has_bias ? ({16'd0, oc} << 2) : 32'd0);
    endfunction

    function automatic logic [31:0] conv_filter_words(
        input logic [15:0] oc,
        input logic [15:0] ic,
        input logic [3:0]  k
    );
        conv_filter_words = {16'd0, oc} * {16'd0, ceil4_groups(ic)}
                          * {28'd0, norm_kernel(k)} * {28'd0, norm_kernel(k)};
    endfunction

    function automatic logic [31:0] tensor_bytes(
        input logic [15:0] c,
        input logic [15:0] h,
        input logic [15:0] w
    );
        tensor_bytes = {16'd0, c} * {16'd0, h} * {16'd0, w};
    endfunction

    function automatic logic [31:0] packed_tensor_bytes(
        input logic [15:0] c,
        input logic [15:0] h,
        input logic [15:0] w
    );
        packed_tensor_bytes = {16'd0, ceil4_groups(c)} * {16'd0, h} * {16'd0, w} * 32'd4;
    endfunction

    function automatic logic [31:0] nonzero_count(input logic [31:0] value);
        nonzero_count = (value == 32'd0) ? 32'd1 : value;
    endfunction

    function automatic logic [15:0] strip_width_for(input logic [15:0] remaining);
        strip_width_for = (remaining > STRIP_MAX) ? STRIP_MAX : remaining;
    endfunction

    function automatic logic [31:0] tile_ifmap_words(
        input logic [15:0] sw,
        input logic [3:0]  k
    );
        tile_ifmap_words = {16'd0, sw} * {28'd0, norm_kernel(k)} * {28'd0, norm_kernel(k)};
    endfunction

    function automatic logic [31:0] tile_output_elems(
        input logic [15:0] sw,
        input logic [15:0] channels
    );
        tile_output_elems = {16'd0, sw} * {16'd0, channels};
    endfunction

    logic filter_done_after_accept;
    logic ifmap_done_after_accept;
    logic ipsum_done_after_accept;
    logic opsum_done_after_accept;
    logic layer_done_after_opsum;

    assign filter_done_after_accept = filter_accept && (filter_count + 32'd1 >= filter_words_total);
    assign ifmap_done_after_accept  = ifmap_accept  && (ifmap_count  + 32'd1 >= row_ifmap_words_total);
    assign ipsum_done_after_accept  = ipsum_accept  && (ipsum_count  + 32'd1 >= row_output_elems_total);
    assign opsum_done_after_accept  = opsum_accept  && (opsum_count  + 32'd1 >= row_output_elems_total);
    assign strip_done_after_opsum   = opsum_done_after_accept
                                    && (strip_ow_base + strip_w >= out_w);
    assign layer_done_after_opsum   = strip_done_after_opsum && (ifmap_oy == out_h - 16'd1);

    always_comb begin
        next = state;
        unique case (state)
            S_IDLE: begin
                if (start_conv)      next = S_LOAD_WGT;
                else if (start_pool) next = S_PE_CONFIG;
                else if (start_add)  next = S_DONE;
            end
            S_LOAD_WGT:  if (wb_fill_done)              next = S_PE_CONFIG;
            S_PE_CONFIG: next = (op_l == EXEC_CONV) ? S_FILTER :
                               (op_l == EXEC_POOL) ? S_IFMAP  : S_DONE;
            S_FILTER:    if (filter_done_after_accept)  next = S_IFMAP;
            S_IFMAP:     if (ifmap_done_after_accept)   next = (op_l == EXEC_CONV) ? S_IPSUM : S_START_OUT;
            S_IPSUM:     if (ipsum_done_after_accept)   next = S_OPSUM;
            S_OPSUM:     if (opsum_done_after_accept)   next = layer_done_after_opsum ? S_START_OUT : S_IFMAP;
            S_START_OUT:                                  next = S_DRAIN;
            S_DRAIN:     if (oc_done)                    next = S_DONE;
            S_DONE:                                      next = S_IDLE;
            default:                                     next = S_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            op_l <= '0;
            in_h <= '0; in_w <= '0; in_c <= '0; out_c <= '0;
            out_h <= '0; out_w <= '0;
            in_addr <= '0; wgt_addr <= '0; out_addr <= '0;
            flags <= '0;
            stride <= 4'd1; pad <= '0; kernel <= 4'd1;
            shift <= '0; lhs_shift <= '0; rhs_shift <= '0; pconfig <= '0;
            sel <= 1'b0;
            weight_bytes_l <= '0; input_bytes_l <= '0; output_bytes_l <= '0;
            filter_words_total <= 32'd1;
            ifmap_words_total <= 32'd1;
            output_elems_total <= 32'd1;
            row_ifmap_words_total <= 32'd1;
            row_active_ifmap_words_total <= 32'd1;
            row_output_elems_total <= 32'd1;
            strip_ow_base <= '0;
            strip_w <= 16'd1;
            filter_count <= '0; ifmap_count <= '0; ipsum_count <= '0; opsum_count <= '0;
            ifmap_oy <= '0; ifmap_ow <= '0; ifmap_tap_y <= '0; ifmap_tap_x <= '0;
            ifmap_diag_tag <= '0; ifmap_diag_rep <= '0;
            filter_kcol <= '0; filter_krow <= '0;
            ipsum_ow <= '0; ipsum_oc <= '0; opsum_ow <= '0; opsum_oc <= '0;
        end else begin
            state <= next;

            if (start_conv || start_pool || start_add) begin
                logic [15:0] out_h_calc;
                logic [15:0] out_w_calc;
                logic [31:0] input_stream_bytes_calc;
                logic [31:0] output_bytes_calc;
                logic [31:0] param_bytes_calc;
                logic [31:0] filter_words_calc;
                logic [31:0] line_words_calc;
                logic [31:0] output_elems_calc;
                logic [31:0] row_line_words_calc;
                logic [31:0] row_active_line_words_calc;
                logic [31:0] row_output_elems_calc;
                logic [31:0] out_channel_calc;
                logic [15:0] strip_w_calc;

                out_h_calc = (exec_op == EXEC_ADD)
                           ? exec_in_h
                           : calc_out_dim(exec_in_h, exec_pad, exec_kernel, exec_stride);
                out_w_calc = (exec_op == EXEC_ADD)
                           ? exec_in_w
                           : calc_out_dim(exec_in_w, exec_pad, exec_kernel, exec_stride);

                input_stream_bytes_calc = (exec_op == EXEC_ADD)
                                        ? tensor_bytes(exec_in_c, exec_in_h, exec_in_w)
                                        : packed_tensor_bytes(exec_in_c, exec_in_h, exec_in_w);
                output_elems_calc = (exec_op == EXEC_ADD)
                                  ? tensor_bytes(exec_in_c, exec_in_h, exec_in_w)
                                  : tensor_bytes((exec_op == EXEC_POOL) ? exec_in_c : exec_out_c,
                                                 out_h_calc, out_w_calc);
                output_bytes_calc = (exec_op == EXEC_ADD)
                                  ? output_elems_calc
                                  : packed_tensor_bytes((exec_op == EXEC_POOL) ? exec_in_c : exec_out_c,
                                                        out_h_calc, out_w_calc);
                param_bytes_calc  = (exec_op == EXEC_CONV)
                                  ? conv_param_bytes(exec_out_c, exec_in_c, exec_kernel,
                                                     exec_flags[`FLAG_BIAS])
                                  : 32'd0;
                filter_words_calc = (exec_op == EXEC_CONV)
                                  ? conv_filter_words(exec_out_c, exec_in_c, exec_kernel)
                                  : 32'd1;
                row_line_words_calc = {16'd0, out_w_calc}
                                    * {28'd0, norm_kernel(exec_kernel)}
                                    * {28'd0, norm_kernel(exec_kernel)};
                row_active_line_words_calc = ({16'd0, out_w_calc} + {28'd0, norm_kernel(exec_kernel)} - 32'd1)
                                           * {28'd0, norm_kernel(exec_kernel)};
                line_words_calc     = {16'd0, out_h_calc} * row_line_words_calc;
                out_channel_calc    = (exec_op == EXEC_POOL) ? {16'd0, exec_in_c}
                                                              : {16'd0, exec_out_c};
                strip_w_calc = strip_width_for(out_w_calc);
                row_line_words_calc = (exec_op == EXEC_CONV)
                                    ? ({28'd0, norm_kernel(exec_kernel)} * {28'd0, norm_kernel(exec_kernel)})
                                    : tile_ifmap_words(strip_w_calc, exec_kernel);
                row_active_line_words_calc = row_line_words_calc;
                row_output_elems_calc = (exec_op == EXEC_CONV)
                                      ? out_channel_calc
                                      : tile_output_elems(strip_w_calc, out_channel_calc[15:0]);

                op_l <= exec_op;
                in_h <= exec_in_h; in_w <= exec_in_w;
                in_c <= exec_in_c; out_c <= exec_out_c;
                out_h <= out_h_calc; out_w <= out_w_calc;
                in_addr <= exec_in_addr; wgt_addr <= exec_wgt_addr; out_addr <= exec_out_addr;
                flags <= exec_flags;
                stride <= exec_stride; pad <= exec_pad; kernel <= norm_kernel(exec_kernel);
                shift <= exec_shift; lhs_shift <= exec_lhs_shift; rhs_shift <= exec_rhs_shift;
                pconfig <= exec_pconfig;
                weight_bytes_l <= align4(param_bytes_calc);
                input_bytes_l <= align4(input_stream_bytes_calc);
                output_bytes_l <= align4(output_bytes_calc);
                filter_words_total <= nonzero_count(filter_words_calc);
                ifmap_words_total <= nonzero_count(line_words_calc);
                output_elems_total <= nonzero_count(output_elems_calc);
                row_ifmap_words_total <= nonzero_count(row_line_words_calc);
                row_active_ifmap_words_total <= nonzero_count(row_active_line_words_calc);
                row_output_elems_total <= nonzero_count(row_output_elems_calc);
                strip_ow_base <= '0;
                strip_w <= (strip_w_calc == 16'd0) ? 16'd1 : strip_w_calc;
                filter_count <= '0; ifmap_count <= '0; ipsum_count <= '0; opsum_count <= '0;
                ifmap_oy <= '0; ifmap_ow <= '0; ifmap_tap_y <= '0; ifmap_tap_x <= '0;
                ifmap_diag_tag <= '0; ifmap_diag_rep <= '0;
                filter_kcol <= '0; filter_krow <= '0;
                ipsum_ow <= '0; ipsum_oc <= '0; opsum_ow <= '0; opsum_oc <= '0;
            end else begin
                if (state == S_FILTER && filter_accept) begin
                    if (filter_done_after_accept) begin
                        filter_count <= '0;
                        filter_kcol <= '0;
                        filter_krow <= '0;
                    end else begin
                        filter_count <= filter_count + 32'd1;
                        if (filter_kcol == kernel - 4'd1) begin
                            filter_kcol <= '0;
                            if (filter_krow == kernel - 4'd1) filter_krow <= '0;
                            else                              filter_krow <= filter_krow + 4'd1;
                        end else begin
                            filter_kcol <= filter_kcol + 4'd1;
                        end
                    end
                end

                if (state == S_IFMAP && ifmap_accept) begin
                    if (ifmap_done_after_accept) begin
                        ifmap_count <= '0;
                        ifmap_ow <= '0; ifmap_tap_y <= '0; ifmap_tap_x <= '0;
                        ifmap_diag_tag <= '0; ifmap_diag_rep <= '0;
                    end else begin
                        ifmap_count <= ifmap_count + 32'd1;
                        if (ifmap_count + 32'd1 < row_active_ifmap_words_total) begin
                            if (ifmap_diag_rep == kernel - 4'd1) begin
                                ifmap_diag_rep <= '0;
                                ifmap_diag_tag <= ifmap_diag_tag + 1'b1;
                            end else begin
                                ifmap_diag_rep <= ifmap_diag_rep + 4'd1;
                            end
                        end
                        if (ifmap_tap_x == kernel - 4'd1) begin
                            ifmap_tap_x <= '0;
                            if (ifmap_tap_y == kernel - 4'd1) begin
                                ifmap_tap_y <= '0;
                                if (ifmap_ow == strip_w - 16'd1) begin
                                    ifmap_ow <= '0;
                                end else begin
                                    ifmap_ow <= ifmap_ow + 16'd1;
                                end
                            end else begin
                                ifmap_tap_y <= ifmap_tap_y + 4'd1;
                            end
                        end else begin
                            ifmap_tap_x <= ifmap_tap_x + 4'd1;
                        end
                    end
                end

                if (state == S_IPSUM && ipsum_accept) begin
                    if (ipsum_done_after_accept) begin
                        ipsum_count <= '0;
                        ipsum_ow <= '0;
                        ipsum_oc <= '0;
                    end else begin
                        ipsum_count <= ipsum_count + 32'd1;
                        if (ipsum_oc == out_c - 16'd1) begin
                            ipsum_oc <= '0;
                            if (ipsum_ow == strip_w - 16'd1) ipsum_ow <= '0;
                            else                           ipsum_ow <= ipsum_ow + 16'd1;
                        end else begin
                            ipsum_oc <= ipsum_oc + 16'd1;
                        end
                    end
                end

                if (state == S_OPSUM && opsum_accept) begin
                    if (opsum_done_after_accept) begin
                        logic [15:0] next_strip_w;
                        logic [15:0] next_out_ch;

                        opsum_count <= '0;
                        opsum_ow <= '0;
                        opsum_oc <= '0;
                        if (strip_ow_base + strip_w >= out_w) begin
                            strip_ow_base <= '0;
                            next_strip_w = strip_width_for(out_w);
                            strip_w <= next_strip_w;
                            if (ifmap_oy == out_h - 16'd1) ifmap_oy <= '0;
                            else                           ifmap_oy <= ifmap_oy + 16'd1;
                        end else begin
                            strip_ow_base <= strip_ow_base + strip_w;
                            next_strip_w = strip_width_for(out_w - (strip_ow_base + strip_w));
                            strip_w <= next_strip_w;
                        end

                        next_out_ch = (op_l == EXEC_POOL) ? in_c : out_c;
                        row_ifmap_words_total <= nonzero_count((op_l == EXEC_CONV)
                                                            ? ({28'd0, kernel} * {28'd0, kernel})
                                                            : tile_ifmap_words(next_strip_w, kernel));
                        row_active_ifmap_words_total <= nonzero_count((op_l == EXEC_CONV)
                                                                   ? ({28'd0, kernel} * {28'd0, kernel})
                                                                   : tile_ifmap_words(next_strip_w, kernel));
                        row_output_elems_total <= nonzero_count((op_l == EXEC_CONV)
                                                             ? {16'd0, next_out_ch}
                                                             : tile_output_elems(next_strip_w, next_out_ch));
                    end else begin
                        opsum_count <= opsum_count + 32'd1;
                        if (opsum_oc == out_c - 16'd1) begin
                            opsum_oc <= '0;
                            if (opsum_ow == strip_w - 16'd1) opsum_ow <= '0;
                            else                           opsum_ow <= opsum_ow + 16'd1;
                        end else begin
                            opsum_oc <= opsum_oc + 16'd1;
                        end
                    end
                end

                if (state == S_DONE) sel <= ~sel;
            end
        end
    end

    assign wb_fill_start = start_conv;
    assign wb_fill_addr  = start_conv ? exec_wgt_addr[`SRAM_ADDR_BITS-1:0]
                                      : wgt_addr[`SRAM_ADDR_BITS-1:0];
    assign wb_fill_bytes = start_conv ? align4(conv_param_bytes(exec_out_c, exec_in_c, exec_kernel,
                                                                exec_flags[`FLAG_BIAS]))
                                      : weight_bytes_l;
    assign wb_sel        = sel;

    assign iob_swap      = sel;
    assign iob_in_start  = (state == S_PE_CONFIG) && (op_l != EXEC_ADD);
    assign iob_in_addr   = in_addr[`SRAM_ADDR_BITS-1:0];
    assign iob_in_len    = input_bytes_l;
    assign iob_out_start = (state == S_PE_CONFIG);
    assign iob_out_addr  = out_addr[`SRAM_ADDR_BITS-1:0];
    assign iob_out_len   = output_bytes_l;

    assign lb_flush      = (state == S_PE_CONFIG) && (op_l != EXEC_ADD);
    assign lb_row_width  = in_w;
    assign lb_kernel     = kernel;
    assign pe_tile_start = (state == S_OPSUM) && opsum_done_after_accept && !layer_done_after_opsum;

    logic [4:0] out_ch_cfg;
    logic [3:0] stride_cfg;
    logic [15:0] stride_cfg_wide;
    assign out_ch_cfg = (out_c == 16'd0) ? 5'd0 :
                        (out_c > 16'd32) ? 5'd31 : (out_c[4:0] - 5'd1);
    assign stride_cfg_wide = norm_stride(stride);
    assign stride_cfg = stride_cfg_wide[3:0];
    assign pe_config  = {9'd0, out_ch_cfg, stride_cfg, norm_kernel(kernel), pconfig};

    always_comb begin
        unique case (state)
            S_FILTER: glb_sel = 2'd1;
            S_IFMAP:  glb_sel = 2'd0;
            S_IPSUM:  glb_sel = 2'd2;
            S_OPSUM:  glb_sel = 2'd3;
            default:  glb_sel = 2'd0;
        endcase
    end

    // Dynamic tag walk for the current Step-1 stream order.  The tags are
    // bounded by the physical array ID width and remain stable unless a
    // corresponding valid/ready transfer is accepted.
    assign ifmap_tag_x_wide = ifmap_ow;
    assign ifmap_tag_x_calc = (ifmap_count < row_active_ifmap_words_total)
                            ? ifmap_tag_x_wide[`XID_BITS-1:0]
                            : {`XID_BITS{1'b1}} - {{(`XID_BITS-1){1'b0}}, 1'b1};

    assign filter_tag_X = {{(`XID_BITS-4){1'b0}}, filter_krow};
    assign filter_tag_Y = '0;
    assign ifmap_tag_X  = ifmap_tag_x_calc;
    assign ifmap_tag_Y  = {{(`YID_BITS-4){1'b0}}, ifmap_tap_y};
    assign ipsum_tag_X  = ipsum_ow[`XID_BITS-1:0];
    assign ipsum_tag_Y  = '0;
    assign opsum_tag_X  = opsum_ow[`XID_BITS-1:0];
    assign opsum_tag_Y  = '0;

    assign pp_ipsum_valid = (state == S_IPSUM);
    assign ifmap_en       = (state == S_IFMAP);

    assign ppu_shift        = shift;
    assign ppu_silu_en      = flags[`FLAG_SIGMOID] && flags[`FLAG_MULTIPLY];
    assign ppu_maxpool_en   = (op_l == EXEC_POOL);
    assign ppu_maxpool_init = (op_l == EXEC_POOL) && (ifmap_count == 32'd0);

    assign oc_layer_start = (state == S_PE_CONFIG);
    assign oc_bias_en     = (op_l == EXEC_CONV) && flags[`FLAG_BIAS];
    assign oc_pixel_init  = opsum_accept;
    assign oc_pixel_last  = opsum_accept;
    assign oc_lane_sel    = opsum_oc[3:0];
    assign oc_layer_last  = layer_done_after_opsum;
    assign oc_spatial_mode    = (op_l == EXEC_CONV);
    assign oc_spatial_cols    = strip_w;
    assign oc_spatial_groups  = ceil4_groups((op_l == EXEC_POOL) ? in_c : out_c);
    assign oc_spatial_channel = opsum_oc[4:0];
    assign oc_spatial_tile_last = opsum_accept && opsum_done_after_accept;
    assign oc_spatial_last    = opsum_accept && layer_done_after_opsum;

    assign add_en        = (op_l == EXEC_ADD);
    assign add_lhs_shift = lhs_shift;
    assign add_rhs_shift = rhs_shift;

    assign exec_done = (state == S_DONE);

    logic unused_inputs;
    assign unused_inputs = ^{iob_in_done, iob_out_done, exec_stride, exec_pad};
endmodule
