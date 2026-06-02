`include "define.svh"

// IOMap_Buffer
//
// INPUT_READ mode:
//   - linear mode keeps the original word-by-word SRAM stream;
//   - pack_nchw_read mode gathers NCHW activation bytes into one 4-lane
//     word per spatial position: lane[c] = SRAM[base + c*H*W + pixel].
//     Missing lanes are filled with uint8 zero-point 128.
//
// OUTPUT_WRITE mode:
//   - linear mode keeps the original word-by-word SRAM write;
//   - unpack_nchw_write mode scatters a 4-lane activation word back to NCHW:
//     SRAM[base + c*H*W + pixel] = lane[c], with read-modify-write for the
//     byte lane inside the 32-bit SRAM word.
module IOMap_Buffer #(
    parameter DEPTH = (64*1024) / (`DATA_BITS/8),
    parameter MAX_GROUPS = 64
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         mode_write,             // 0 = INPUT_READ, 1 = OUTPUT_WRITE
    input  logic         start,
    input  logic [`SRAM_ADDR_BITS-1:0] base_addr,
    input  logic [31:0]  length,                 // stream bytes, rounded to words
    input  logic         pack_nchw_read,
    input  logic         unpack_nchw_write,
    input  logic [15:0]  tensor_c,
    input  logic [15:0]  tensor_h,
    input  logic [15:0]  tensor_w,
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
    typedef enum logic [3:0] {
        S_IDLE,
        S_RD_ISSUE,
        S_RD_OUT,
        S_PACK_READ,
        S_WR_LINEAR,
        S_WR_ACCEPT,
        S_WR_READ,
        S_WR_COMMIT,
        S_DONE
    } state_t;
    state_t state, next;

    logic [31:0] words_total;
    logic [31:0] word_idx;
    logic [`SRAM_ADDR_BITS-1:0] cur_addr;
    logic [`DATA_BITS-1:0] rd_reg;

    logic [31:0] spatial_total;
    logic [15:0] groups_total;
    logic [31:0] pixel_idx;
    logic [15:0] group_idx;
    logic [1:0]  lane_idx;

    logic [`DATA_BITS-1:0] wr_pack;
    logic [`DATA_BITS-1:0] wr_rd_word;
    logic [1:0]            wr_lane;
    logic [1:0]            wr_byte_pos;
    logic [15:0]           burst_group_idx;
    logic [31:0]           burst_pixel_base;
    logic                  burst_last;
    logic [`DATA_BITS-1:0] accum_word [0:MAX_GROUPS-1][0:3];
    logic [`DATA_BITS-1:0] burst_word [0:3];

    logic pack_read_l;
    logic unpack_write_l;
    logic fast_unpack;
    logic [15:0] tensor_c_l, tensor_h_l, tensor_w_l;

    logic [15:0] lane_channel;
    logic [31:0] byte_addr_calc;
    logic [1:0]  byte_sel;
    logic [7:0]  selected_byte;
    logic [7:0]  wr_lane_byte;
    logic [`DATA_BITS-1:0] wr_merged_word;

    function automatic logic [15:0] ceil4_groups(input logic [15:0] channels);
        ceil4_groups = (channels + 16'd3) >> 2;
    endfunction

    assign lane_channel = (group_idx << 2) + {14'd0, (state == S_WR_READ || state == S_WR_COMMIT) ? wr_lane : lane_idx};
    assign byte_addr_calc = {10'd0, lane_channel} * spatial_total + pixel_idx + base_addr;
    assign byte_sel = byte_addr_calc[1:0];

    always_comb begin
        unique case (byte_sel)
            2'd0: selected_byte = sram_rdata[7:0];
            2'd1: selected_byte = sram_rdata[15:8];
            2'd2: selected_byte = sram_rdata[23:16];
            default: selected_byte = sram_rdata[31:24];
        endcase
    end

    assign wr_lane_byte = wr_pack[wr_lane*8 +: 8];
    assign fast_unpack = unpack_write_l && (spatial_total[1:0] == 2'b00);

    always_comb begin
        wr_merged_word = wr_rd_word;
        unique case (byte_sel)
            2'd0: wr_merged_word[7:0]   = wr_lane_byte;
            2'd1: wr_merged_word[15:8]  = wr_lane_byte;
            2'd2: wr_merged_word[23:16] = wr_lane_byte;
            default: wr_merged_word[31:24] = wr_lane_byte;
        endcase
    end

    always_comb begin
        next = state;
        unique case (state)
            S_IDLE: begin
                if (start) begin
                    if (mode_write) next = unpack_nchw_write ? S_WR_ACCEPT : S_WR_LINEAR;
                    else            next = pack_nchw_read    ? S_PACK_READ : S_RD_ISSUE;
                end
            end

            S_RD_ISSUE: next = S_RD_OUT;

            S_PACK_READ: begin
                if (lane_idx == 2'd3) next = S_RD_OUT;
            end

            S_RD_OUT: if (ifmap_ready) begin
                if (word_idx == words_total - 1) next = S_DONE;
                else                             next = pack_read_l ? S_PACK_READ : S_RD_ISSUE;
            end

            S_WR_LINEAR: if (ppu_valid && word_idx == words_total - 1) next = S_DONE;

            S_WR_ACCEPT: if (ppu_valid) begin
                if (fast_unpack && (pixel_idx[1:0] == 2'd3 || word_idx + 32'd1 >= words_total)) begin
                    next = S_WR_COMMIT;
                end else begin
                    next = fast_unpack ? S_WR_ACCEPT : S_WR_READ;
                end
            end

            S_WR_READ: next = S_WR_COMMIT;

            S_WR_COMMIT: begin
                if (fast_unpack) begin
                    if (wr_lane == 2'd3) begin
                        if (burst_last) next = S_DONE;
                        else            next = S_WR_ACCEPT;
                    end
                end else begin
                    if (wr_lane == 2'd3) begin
                        if (word_idx == words_total - 1) next = S_DONE;
                        else                             next = S_WR_ACCEPT;
                    end else begin
                        next = S_WR_READ;
                    end
                end
            end

            S_DONE: next = S_IDLE;
            default: next = S_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            word_idx       <= '0;
            words_total    <= '0;
            cur_addr       <= '0;
            rd_reg         <= '0;
            spatial_total  <= '0;
            groups_total   <= 16'd1;
            pixel_idx      <= '0;
            group_idx      <= '0;
            lane_idx       <= '0;
            wr_pack        <= '0;
            wr_rd_word     <= '0;
            wr_lane        <= '0;
            wr_byte_pos    <= '0;
            burst_group_idx <= '0;
            burst_pixel_base <= '0;
            burst_last     <= 1'b0;
            pack_read_l    <= 1'b0;
            unpack_write_l <= 1'b0;
            tensor_c_l     <= '0;
            tensor_h_l     <= '0;
            tensor_w_l     <= '0;
        end else begin
            state <= next;

            unique case (state)
                S_IDLE: if (start) begin
                    word_idx       <= '0;
                    words_total    <= length >> 2;
                    cur_addr       <= base_addr;
                    rd_reg         <= '0;
                    pixel_idx      <= '0;
                    group_idx      <= '0;
                    lane_idx       <= '0;
                    wr_lane        <= '0;
                    wr_byte_pos    <= '0;
                    burst_group_idx <= '0;
                    burst_pixel_base <= '0;
                    burst_last     <= 1'b0;
                    pack_read_l    <= pack_nchw_read;
                    unpack_write_l <= unpack_nchw_write;
                    tensor_c_l     <= tensor_c;
                    tensor_h_l     <= tensor_h;
                    tensor_w_l     <= tensor_w;
                    spatial_total  <= {16'd0, tensor_h} * {16'd0, tensor_w};
                    groups_total   <= ceil4_groups(tensor_c);
                    for (int g = 0; g < MAX_GROUPS; g++) begin
                        for (int l = 0; l < 4; l++) begin
                            accum_word[g][l] <= '0;
                        end
                    end
                end

                S_RD_ISSUE: begin
                    rd_reg <= sram_rdata;
                end

                S_PACK_READ: begin
                    if (lane_channel < tensor_c_l) begin
                        rd_reg[lane_idx*8 +: 8] <= selected_byte;
                    end else begin
                        rd_reg[lane_idx*8 +: 8] <= 8'd128;
                    end
                    lane_idx <= lane_idx + 2'd1;
                end

                S_RD_OUT: if (ifmap_ready) begin
                    word_idx <= word_idx + 1'b1;
                    cur_addr <= cur_addr + 'd4;
                    lane_idx <= '0;
                    if (pack_read_l) begin
                        if (group_idx == groups_total - 16'd1) begin
                            group_idx <= '0;
                            pixel_idx <= pixel_idx + 32'd1;
                        end else begin
                            group_idx <= group_idx + 16'd1;
                        end
                    end
                end

                S_WR_LINEAR: if (ppu_valid) begin
                    word_idx <= word_idx + 1'b1;
                    cur_addr <= cur_addr + 'd4;
                end

                S_WR_ACCEPT: if (ppu_valid) begin
                    logic [`DATA_BITS-1:0] merged [0:3];

                    wr_pack <= ppu_data;
                    wr_lane <= '0;

                    if (fast_unpack) begin
                        wr_byte_pos <= pixel_idx[1:0];
                        for (int l = 0; l < 4; l++) begin
                            merged[l] = accum_word[group_idx[5:0]][l];
                            merged[l][pixel_idx[1:0]*8 +: 8] = ppu_data[l*8 +: 8];
                            accum_word[group_idx[5:0]][l] <= merged[l];
                            if (pixel_idx[1:0] == 2'd3 || word_idx + 32'd1 >= words_total) begin
                                burst_word[l] <= merged[l];
                            end
                        end
                        if (pixel_idx[1:0] == 2'd3 || word_idx + 32'd1 >= words_total) begin
                            burst_group_idx  <= group_idx;
                            burst_pixel_base <= {pixel_idx[31:2], 2'b00};
                            burst_last       <= (word_idx + 32'd1 >= words_total);
                        end

                        word_idx <= word_idx + 1'b1;
                        if (group_idx == groups_total - 16'd1) begin
                            group_idx <= '0;
                            pixel_idx <= pixel_idx + 32'd1;
                        end else begin
                            group_idx <= group_idx + 16'd1;
                        end
                    end
                end

                S_WR_READ: begin
                    wr_rd_word <= sram_rdata;
                end

                S_WR_COMMIT: begin
                    if (fast_unpack) begin
                        if (wr_lane == 2'd3) begin
                            wr_lane <= '0;
                        end else begin
                            wr_lane <= wr_lane + 2'd1;
                        end
                    end else begin
                        if (wr_lane == 2'd3) begin
                            word_idx <= word_idx + 1'b1;
                            wr_lane  <= '0;
                            if (group_idx == groups_total - 16'd1) begin
                                group_idx <= '0;
                                pixel_idx <= pixel_idx + 32'd1;
                            end else begin
                                group_idx <= group_idx + 16'd1;
                            end
                        end else begin
                            wr_lane <= wr_lane + 2'd1;
                        end
                    end
                end

                default: ;
            endcase
        end
    end

    always_comb begin
        sram_en    = 1'b0;
        sram_we    = 1'b0;
        sram_addr  = cur_addr;
        sram_wdata = '0;

        unique case (state)
            S_RD_ISSUE: begin
                sram_en   = 1'b1;
                sram_addr = cur_addr;
            end

            S_PACK_READ: if (lane_channel < tensor_c_l) begin
                sram_en   = 1'b1;
                sram_addr = byte_addr_calc[`SRAM_ADDR_BITS-1:0];
            end

            S_WR_LINEAR: if (ppu_valid) begin
                sram_en    = 1'b1;
                sram_we    = 1'b1;
                sram_addr  = cur_addr;
                sram_wdata = ppu_data;
            end

            S_WR_READ: if (lane_channel < tensor_c_l) begin
                sram_en   = 1'b1;
                sram_addr = byte_addr_calc[`SRAM_ADDR_BITS-1:0];
            end

            S_WR_COMMIT: begin
                if (fast_unpack) begin
                    logic [15:0] burst_channel;
                    logic [31:0] burst_byte_addr;

                    burst_channel = (burst_group_idx << 2) + {14'd0, wr_lane};
                    burst_byte_addr = base_addr
                                    + ({16'd0, burst_channel} * spatial_total)
                                    + burst_pixel_base;
                    if (burst_channel < tensor_c_l) begin
                        sram_en    = 1'b1;
                        sram_we    = 1'b1;
                        sram_addr  = burst_byte_addr[`SRAM_ADDR_BITS-1:0];
                        sram_wdata = burst_word[wr_lane];
                    end
                end else if (lane_channel < tensor_c_l) begin
                    sram_en    = 1'b1;
                    sram_we    = 1'b1;
                    sram_addr  = byte_addr_calc[`SRAM_ADDR_BITS-1:0];
                    sram_wdata = wr_merged_word;
                end
            end

            default: ;
        endcase
    end

    assign ifmap_data  = rd_reg;
    assign ifmap_valid = (state == S_RD_OUT);
    assign ppu_ready   = unpack_write_l ? (state == S_WR_ACCEPT)
                                        : (state == S_WR_LINEAR);
    assign done        = (state == S_DONE);

endmodule
