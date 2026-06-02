`include "define.svh"
// OpsumCollector: opsum-stream to PSUM_acc adapter.
//
// PE_array (via the GON) emits the gathered output partial sums as a
// valid/ready stream on GLB_data_out. The 16 PSUM_acc lanes use an
// init / accum_en / last protocol. OpsumCollector bridges the two:
//   - drives opsum_ready back to the PE array
//   - routes each opsum word to the PSUM lane named by lane_sel
//   - turns pixel_init / pixel_last into per-lane init / last pulses
//   - holds the per-layer INT32 bias table (loaded from Weight_Buffer) and
//     presents it on psum_bias so PSUM_acc can seed the accumulator
//   - drains completed PSUM_acc lanes one at a time through the single shared
//     PPU (a combinational datapath with no handshake of its own)
//   - packs four int8 PPU results into one 32-bit activation word and streams
//     it to the IOMap_Buffer with a valid/ready handshake
//
// FSM: IDLE -> BIAS_LOAD -> COLLECT (drain runs concurrently as lanes complete)
//      -> DRAIN_TAIL -> DONE.
module OpsumCollector #(
    parameter LANES = `NUMS_PE_COL
)(
    input  logic clk,
    input  logic rst,

    // Control from PingPong_Ctrl.
    input  logic         layer_start,
    input  logic         bias_en,
    input  logic         pixel_init,
    input  logic         pixel_last,
    input  logic         layer_last,   // HIGH only on final opsum_accept of the layer
    input  logic [3:0]   lane_sel,
    input  logic         spatial_mode,
    input  logic [15:0]  spatial_cols,
    input  logic [15:0]  spatial_groups,
    input  logic [4:0]   spatial_channel,
    input  logic         spatial_valid,
    input  logic         spatial_tile_last,
    input  logic         spatial_last,
    input  logic [LANES*`PSUM_BITS-1:0] spatial_data_flat,
    output logic         spatial_ready,
    input  logic [5:0]   ppu_shift_ctrl,
    input  logic         ppu_silu_en_ctrl,
    input  logic         ppu_maxpool_en_ctrl,
    input  logic         ppu_maxpool_init_ctrl,

    // Bias stream from Weight_Buffer.
    input  logic         bias_valid,
    input  logic signed [`PSUM_BITS-1:0] bias_word,
    output logic         bias_ready,

    // Opsum stream from PE_array (GON).
    input  logic         opsum_valid,
    input  logic signed [`PSUM_BITS-1:0] opsum_data,
    output logic         opsum_ready,

    // To PSUM_acc x16.
    output logic signed [`PSUM_BITS-1:0]       psum_data,
    output logic [LANES*`PSUM_BITS-1:0]        psum_bias,
    output logic [LANES-1:0]                   psum_init,
    output logic [LANES-1:0]                   psum_accum_en,
    output logic [LANES-1:0]                   psum_last,
    input  logic [LANES-1:0]                   psum_complete,
    input  logic [LANES*`PSUM_BITS-1:0]        psum_out_flat,   // PSUM_acc[i].psum_out

    // To / from PPU (single shared PPU, combinational, no handshake).
    output logic [`DATA_BITS-1:0] ppu_data_in,
    input  logic [7:0]            ppu_data_out,

    // Packed activation stream to IOMap_Buffer.
    output logic [`DATA_BITS-1:0] act_data,
    output logic                  act_valid,
    input  logic                  act_ready,

    // Reports layer end so PingPong_Ctrl can wait for the last act_data
    // to drain into IOMap_Buffer before pulsing exec_done.
    output logic                  done
);
    typedef enum logic [2:0] {
        S_IDLE, S_BIAS_LOAD, S_COLLECT, S_DRAIN_TAIL, S_DONE
    } state_t;
    state_t state, next;

    // Per-lane bias storage. Held at zero when bias_en is low.
    logic signed [`PSUM_BITS-1:0] bias_buf [0:LANES-1];
    logic [$clog2(LANES+1)-1:0] bias_cnt;

    // Drain queue
    logic [LANES-1:0] drain_pending;

    // PPU walk pointer + 4-lane pack staging.
    logic [$clog2(LANES)-1:0] drain_idx;
    logic [1:0] pack_cnt;
    logic [`DATA_BITS-1:0] pack_buf;     // 4 int8s assembled here
    logic                  pack_valid;   // act_valid pending

    logic layer_last_seen;
    logic spatial_emit_active;
    logic [$clog2(LANES)-1:0] spatial_emit_col;
    logic [3:0] spatial_emit_group;
    localparam int SPATIAL_GROUP_SLOTS = (LANES + 3) / 4;
    logic [`DATA_BITS-1:0] spatial_pack [0:LANES-1][0:SPATIAL_GROUP_SLOTS-1];

    function automatic logic [7:0] spatial_ppu_byte(
        input logic signed [`PSUM_BITS-1:0] psum_in,
        input logic [5:0] shift_in,
        input logic silu_en_in
    );
        logic signed [`PSUM_BITS-1:0] shifted;
        logic signed [7:0] q;
        begin
            shifted = psum_in >>> shift_in;
            if (shifted > 32'sd127)       q = 8'sd127;
            else if (shifted < -32'sd128) q = -8'sd128;
            else                          q = shifted[7:0];

            // Matches the current 256-entry SiLU LUT: negative int8 values map
            // to zero, non-negative values pass through.
            if (silu_en_in && q[7]) q = 8'sd0;
            spatial_ppu_byte = q[7:0] + 8'd128;
        end
    endfunction

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_IDLE:       if (layer_start)
                              next = bias_en ? S_BIAS_LOAD : S_COLLECT;
            S_BIAS_LOAD:  if (bias_cnt == LANES) next = S_COLLECT;
            S_COLLECT: begin
                if (spatial_mode) begin
                    if (layer_last_seen && !spatial_emit_active)
                        next = S_DRAIN_TAIL;
                end else if (layer_last_seen && (drain_pending | psum_complete) == '0 && !pack_valid) begin
                    next = S_DRAIN_TAIL;
                end
            end
            S_DRAIN_TAIL: if (spatial_mode || !pack_valid) next = S_DONE;
            S_DONE:                              next = S_IDLE;
            default:                             next = S_IDLE;
        endcase
    end


    logic [$clog2(LANES)-1:0] drain_lane;
    always_comb begin
        drain_lane = '0;
        for (int k = 0; k < LANES; k++) begin
            if (drain_pending[(drain_idx + k) % LANES]) begin
                drain_lane = (drain_idx + k) % LANES;
                break;
            end
        end
    end

    integer k;
    always_ff @(posedge clk) begin
        if (rst) begin
            state            <= S_IDLE;
            bias_cnt         <= '0;
            drain_pending    <= '0;
            drain_idx        <= '0;
            pack_cnt         <= '0;
            pack_buf         <= '0;
            pack_valid       <= 1'b0;
            layer_last_seen  <= 1'b0;
            spatial_emit_active <= 1'b0;
            spatial_emit_col <= '0;
            spatial_emit_group <= '0;
            for (k = 0; k < LANES; k++) bias_buf[k] <= '0;
            for (k = 0; k < LANES; k++) begin
                for (int g = 0; g < SPATIAL_GROUP_SLOTS; g++) begin
                    spatial_pack[k][g] <= '0;
                end
            end
        end else begin
            state <= next;

            case (state)
                S_IDLE: if (layer_start) begin
                    bias_cnt        <= '0;
                    drain_pending   <= '0;
                    drain_idx       <= '0;
                    pack_cnt        <= '0;
                    pack_valid      <= 1'b0;
                    layer_last_seen <= 1'b0;
                    spatial_emit_active <= 1'b0;
                    spatial_emit_col <= '0;
                    spatial_emit_group <= '0;
                    if (!bias_en) begin
                        for (k = 0; k < LANES; k++) bias_buf[k] <= '0;
                    end
                    for (k = 0; k < LANES; k++) begin
                        for (int g = 0; g < SPATIAL_GROUP_SLOTS; g++) begin
                            spatial_pack[k][g] <= '0;
                        end
                    end
                end

                S_BIAS_LOAD: if (bias_valid && bias_cnt < LANES) begin
                    bias_buf[bias_cnt] <= bias_word;
                    bias_cnt           <= bias_cnt + 1'b1;
                end

                S_COLLECT, S_DRAIN_TAIL: begin
                    if (spatial_mode) begin
                        if (state == S_COLLECT && spatial_valid && spatial_ready) begin
                            for (k = 0; k < LANES; k++) begin
                                if (k < spatial_cols && spatial_channel[4:2] < SPATIAL_GROUP_SLOTS) begin
                                    spatial_pack[k][spatial_channel[4:2]][spatial_channel[1:0]*8 +: 8]
                                        <= spatial_ppu_byte(
                                               $signed(spatial_data_flat[k*`PSUM_BITS +: `PSUM_BITS])
                                             + bias_buf[spatial_channel[$clog2(LANES)-1:0]],
                                               ppu_shift_ctrl,
                                               ppu_silu_en_ctrl);
                                end
                            end
                            if (spatial_tile_last) begin
                                spatial_emit_active <= 1'b1;
                                spatial_emit_col <= '0;
                                spatial_emit_group <= '0;
                            end
                            if (spatial_last) layer_last_seen <= 1'b1;
                        end

                        if (spatial_emit_active && act_ready) begin
                            if ({12'd0, spatial_emit_group} + 16'd1 >= spatial_groups) begin
                                spatial_emit_group <= '0;
                                if ({16'd0, spatial_emit_col} + 16'd1 >= spatial_cols) begin
                                    spatial_emit_active <= 1'b0;
                                    spatial_emit_col <= '0;
                                end else begin
                                    spatial_emit_col <= spatial_emit_col + 1'b1;
                                end
                            end else begin
                                spatial_emit_group <= spatial_emit_group + 1'b1;
                            end
                        end
                    end else begin
                        // Mark lanes whose reduction just finished as pending drain.
                        for (k = 0; k < LANES; k++) begin
                            if (psum_complete[k]) drain_pending[k] <= 1'b1;
                        end

                        // Track layer end
                        if (state == S_COLLECT && opsum_valid && layer_last && opsum_ready)
                            layer_last_seen <= 1'b1;

                        // Walk one pending lane per cycle through the PPU; pack 4
                        // int8 results into one 32-bit word.
                        if (drain_pending != '0 && !pack_valid) begin
                            // FIX: Use the combinationally determined drain_lane
                            drain_pending[drain_lane] <= 1'b0;
                            pack_buf[pack_cnt*8 +: 8] <= ppu_data_out;  // uses combinational PPU result
                            pack_cnt  <= pack_cnt + 1'b1;
                            drain_idx <= (drain_lane + 1) % LANES;
                            if (pack_cnt == 2'd3) pack_valid <= 1'b1;
                        end
                        // FIX: Tail flush logic for handling non-multiple of 4 output sizes
                        else if (state == S_DRAIN_TAIL && drain_pending == '0 && pack_cnt > 0 && !pack_valid) begin
                            pack_valid <= 1'b1;
                        end

                        // Hand off packed word to IOMap_Buffer.
                        if (pack_valid && act_ready) begin
                            pack_valid <= 1'b0;
                            pack_cnt   <= '0;
                            pack_buf   <= '0;
                        end
                    end
                end

                default: ;
            endcase
        end
    end

    // Combinational outputs.

    // BIAS_LOAD: accept the bias stream until LANES words are stored.
    assign bias_ready = (state == S_BIAS_LOAD) && (bias_cnt < LANES);

    // Pack the per-lane bias registers into the flat output.
    always_comb begin
        for (int i = 0; i < LANES; i++)
            psum_bias[i*`PSUM_BITS +: `PSUM_BITS] = bias_buf[i];
    end

    // PSUM_acc routing: in COLLECT, broadcast opsum_data and pulse the lane.
    assign psum_data = opsum_data;

    always_comb begin
        psum_init     = '0;
        psum_accum_en = '0;
        psum_last     = '0;
        // Check opsum_ready to ensure we only apply the command when we actually accept
        if (state == S_COLLECT && opsum_valid && opsum_ready) begin
            psum_init[lane_sel]     = pixel_init;
            psum_accum_en[lane_sel] = !pixel_init;
            psum_last[lane_sel]     = pixel_last;
        end
    end


    assign opsum_ready = !spatial_mode && (state == S_COLLECT) && (drain_pending[lane_sel] == 1'b0);
    assign spatial_ready = spatial_mode && (state == S_COLLECT) && !spatial_emit_active
                         && !ppu_maxpool_en_ctrl && !ppu_maxpool_init_ctrl;

    // Feed the selected lane's PSUM output into the PPU
    assign ppu_data_in = psum_out_flat[drain_lane*`PSUM_BITS +: `DATA_BITS];

    // Packed activation handoff.
    assign act_data  = spatial_mode ? spatial_pack[spatial_emit_col][spatial_emit_group] : pack_buf;
    assign act_valid = spatial_mode ? spatial_emit_active : pack_valid;

    assign done = (state == S_DONE);

endmodule
