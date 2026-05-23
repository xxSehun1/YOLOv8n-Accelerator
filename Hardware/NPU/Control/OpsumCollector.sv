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
    input  logic [3:0]   lane_sel,

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

    // Drain queue: a one-hot ring tracking which lanes still need to flow
    // through the PPU. A bit is set when psum_complete[i] pulses; cleared
    // when that lane is sent through the PPU.
    logic [LANES-1:0] drain_pending;

    // PPU walk pointer + 4-lane pack staging.
    logic [3:0] drain_idx;
    logic [1:0] pack_cnt;
    logic [`DATA_BITS-1:0] pack_buf;     // 4 int8s assembled here
    logic                  pack_valid;   // act_valid pending

    // pixel_last sticky: once the controller asserts pixel_last for the last
    // partial, no more opsum words will arrive after the corresponding
    // psum_complete pulses; the FSM uses this to know it can stop COLLECT.
    logic layer_last_seen;

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_IDLE:       if (layer_start)
                              next = bias_en ? S_BIAS_LOAD : S_COLLECT;
            S_BIAS_LOAD:  if (bias_cnt == LANES) next = S_COLLECT;
            S_COLLECT:    if (layer_last_seen && drain_pending == '0 && !pack_valid)
                              next = S_DRAIN_TAIL;
            S_DRAIN_TAIL: if (!pack_valid)       next = S_DONE;
            S_DONE:                              next = S_IDLE;
            default:                             next = S_IDLE;
        endcase
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
            for (k = 0; k < LANES; k++) bias_buf[k] <= '0;
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
                    if (!bias_en) begin
                        for (k = 0; k < LANES; k++) bias_buf[k] <= '0;
                    end
                end

                S_BIAS_LOAD: if (bias_valid && bias_cnt < LANES) begin
                    bias_buf[bias_cnt] <= bias_word;
                    bias_cnt           <= bias_cnt + 1'b1;
                end

                S_COLLECT, S_DRAIN_TAIL: begin
                    // Mark lanes whose reduction just finished as pending drain.
                    for (k = 0; k < LANES; k++)
                        if (psum_complete[k]) drain_pending[k] <= 1'b1;

                    // Track layer end (pixel_last on the last accepted word).
                    if (state == S_COLLECT && opsum_valid && pixel_last)
                        layer_last_seen <= 1'b1;

                    // Walk one pending lane per cycle through the PPU; pack 4
                    // int8 results into one 32-bit word.
                    if (drain_pending != '0 && !pack_valid) begin
                        // Find next set bit starting at drain_idx (linear scan).
                        // Synthesizable as a priority encoder.
                        logic stepped;
                        stepped = 1'b0;
                        for (k = 0; k < LANES; k++) begin
                            if (!stepped && drain_pending[(drain_idx + k) % LANES]) begin
                                automatic int j = (drain_idx + k) % LANES;
                                drain_pending[j] <= 1'b0;
                                pack_buf[pack_cnt*8 +: 8] <= ppu_data_out;  // uses combinational PPU result
                                pack_cnt  <= pack_cnt + 1'b1;
                                drain_idx <= (j + 1) % LANES;
                                if (pack_cnt == 3) pack_valid <= 1'b1;
                                stepped = 1'b1;
                            end
                        end
                    end

                    // Hand off packed word to IOMap_Buffer.
                    if (pack_valid && act_ready) begin
                        pack_valid <= 1'b0;
                        pack_cnt   <= '0;
                        pack_buf   <= '0;
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
        if (state == S_COLLECT && opsum_valid) begin
            psum_init[lane_sel]     = pixel_init;
            psum_accum_en[lane_sel] = !pixel_init;
            psum_last[lane_sel]     = pixel_last;
        end
    end

    // Always accept opsum words while collecting.
    assign opsum_ready = (state == S_COLLECT);

    // Pick which lane's psum currently feeds the PPU (priority scan).
    logic [3:0] drain_lane;
    always_comb begin
        drain_lane = '0;
        for (int k = 0; k < LANES; k++)
            if (drain_pending[(drain_idx + k) % LANES]) begin
                drain_lane = (drain_idx + k) % LANES;
                break;
            end
    end
    assign ppu_data_in = psum_out_flat[drain_lane*`PSUM_BITS +: `DATA_BITS];

    // Packed activation handoff.
    assign act_data  = pack_buf;
    assign act_valid = pack_valid;

    assign done = (state == S_DONE);

endmodule
