`include "define.svh"

// Weight_Buffer: local raw weight staging plus PE-lane repacking.
//
// Compiler format in SRAM:
//   int8 weights: [OC][IC][KH][KW], byte compact
//   int32 bias  : [OC], immediately following weights when FLAGS.BIAS=1
//
// PE stream format:
//   one 32-bit word for each [OC][IC_GROUP4][KH][KW], where byte lanes are
//   input channels IC_GROUP4*4 + lane. Missing lanes are zero weight.
module Weight_Buffer #(
    parameter DEPTH = (64*1024) / (`DATA_BITS/8)
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         fill_start,
    input  logic [`SRAM_ADDR_BITS-1:0] fill_addr,
    input  logic [31:0]  fill_bytes,
    input  logic [15:0]  in_c,
    input  logic [15:0]  out_c,
    input  logic [3:0]   kernel,
    input  logic         bias_en,
    output logic         fill_done,

    // SRAM read port (to fill).
    output logic         sram_en,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    input  logic [`DATA_BITS-1:0]      sram_rdata,

    // PE-array filter feed.
    output logic [`DATA_BITS-1:0] filter_data,
    output logic         filter_valid,
    input  logic         filter_ready,

    // Bias feed to OpsumCollector.
    output logic         bias_valid,
    output logic signed [`PSUM_BITS-1:0] bias_word,
    input  logic         bias_ready
);
    localparam AW = $clog2(DEPTH);

    typedef enum logic [2:0] {
        S_EMPTY, S_FILL_ISSUE, S_FILL_LATCH, S_FULL, S_PRIME, S_READING
    } state_t;
    state_t state, next;

    logic [`DATA_BITS-1:0] mem [0:DEPTH-1];

    logic [AW-1:0]  wr_idx, rd_idx;
    logic [AW:0]    wr_total;
    logic [AW:0]    latched;
    logic [`SRAM_ADDR_BITS-1:0] cur_sram_addr;

    logic [15:0] in_c_l, out_c_l;
    logic [3:0]  kernel_l;
    logic        bias_en_l;
    logic [15:0] ic_groups_l;
    logic [31:0] raw_weight_bytes_l;
    logic [31:0] filter_words_total_l;
    logic [15:0] bias_idx;
    logic signed [`PSUM_BITS-1:0] bias_word_w;
    logic [`DATA_BITS-1:0] filter_data_q;

    function automatic logic [15:0] ceil4_groups(input logic [15:0] channels);
        ceil4_groups = (channels + 16'd3) >> 2;
    endfunction

    function automatic logic [3:0] norm_kernel(input logic [3:0] k);
        norm_kernel = (k == 4'd0) ? 4'd1 : k;
    endfunction

    function automatic logic [7:0] raw_byte(input logic [31:0] byte_idx);
        logic [`DATA_BITS-1:0] word;
        begin
            word = mem[byte_idx[AW+1:2]];
            unique case (byte_idx[1:0])
                2'd0: raw_byte = word[7:0];
                2'd1: raw_byte = word[15:8];
                2'd2: raw_byte = word[23:16];
                default: raw_byte = word[31:24];
            endcase
        end
    endfunction

    function automatic logic [`DATA_BITS-1:0] repack_filter_word(input logic [31:0] stream_idx);
        logic [31:0] kk;
        logic [31:0] per_oc_group;
        logic [31:0] oc;
        logic [31:0] rem;
        logic [31:0] ic_group;
        logic [31:0] kh;
        logic [31:0] kw;
        logic [31:0] ic;
        logic [31:0] raw_idx;
        logic [`DATA_BITS-1:0] packed_word;
        begin
            kk = {28'd0, kernel_l} * {28'd0, kernel_l};
            per_oc_group = {16'd0, ic_groups_l} * kk;
            oc = stream_idx / per_oc_group;
            rem = stream_idx % per_oc_group;
            ic_group = rem / kk;
            rem = rem % kk;
            kh = rem / {28'd0, kernel_l};
            kw = rem % {28'd0, kernel_l};

            packed_word = '0;
            for (int lane = 0; lane < 4; lane++) begin
                ic = (ic_group << 2) + lane[31:0];
                if (ic < {16'd0, in_c_l}) begin
                    raw_idx = (((oc * {16'd0, in_c_l} + ic) * {28'd0, kernel_l} + kh)
                              * {28'd0, kernel_l}) + kw;
                    packed_word[lane*8 +: 8] = raw_byte(raw_idx);
                end else begin
                    packed_word[lane*8 +: 8] = 8'h00;
                end
            end
            repack_filter_word = packed_word;
        end
    endfunction

    function automatic logic signed [`PSUM_BITS-1:0] repack_bias_word(input logic [15:0] idx);
        logic [31:0] base;
        logic [`DATA_BITS-1:0] packed_word;
        begin
            base = raw_weight_bytes_l + ({16'd0, idx} << 2);
            packed_word = {raw_byte(base + 32'd3),
                           raw_byte(base + 32'd2),
                           raw_byte(base + 32'd1),
                           raw_byte(base)};
            repack_bias_word = $signed(packed_word);
        end
    endfunction

    always_comb begin
        next = state;
        unique case (state)
            S_EMPTY:      if (fill_start)                  next = S_FILL_ISSUE;
            S_FILL_ISSUE: if (latched == wr_total)         next = S_FULL;
                          else                             next = S_FILL_LATCH;
            S_FILL_LATCH: if (latched + 1'b1 == wr_total)  next = S_FULL;
                          else                             next = S_FILL_ISSUE;
            S_FULL:                              next = S_PRIME;
            S_PRIME:                             next = S_READING;
            S_READING: if (filter_ready && rd_idx == filter_words_total_l - 1) next = S_EMPTY;
            default:                             next = S_EMPTY;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_EMPTY;
            wr_idx <= '0;
            rd_idx <= '0;
            wr_total <= '0;
            latched <= '0;
            cur_sram_addr <= '0;
            in_c_l <= '0;
            out_c_l <= '0;
            kernel_l <= 4'd1;
            bias_en_l <= 1'b0;
            ic_groups_l <= 16'd1;
            raw_weight_bytes_l <= '0;
            filter_words_total_l <= 32'd1;
            bias_idx <= '0;
            filter_data_q <= '0;
        end else begin
            state <= next;

            unique case (state)
                S_EMPTY: if (fill_start) begin
                    wr_idx <= '0;
                    rd_idx <= '0;
                    latched <= '0;
                    wr_total <= fill_bytes[AW+2:2];
                    cur_sram_addr <= fill_addr;
                    in_c_l <= in_c;
                    out_c_l <= out_c;
                    kernel_l <= norm_kernel(kernel);
                    bias_en_l <= bias_en;
                    ic_groups_l <= ceil4_groups(in_c);
                    raw_weight_bytes_l <= {16'd0, out_c} * {16'd0, in_c}
                                        * {28'd0, norm_kernel(kernel)}
                                        * {28'd0, norm_kernel(kernel)};
                    filter_words_total_l <= {16'd0, out_c} * {16'd0, ceil4_groups(in_c)}
                                          * {28'd0, norm_kernel(kernel)}
                                          * {28'd0, norm_kernel(kernel)};
                    bias_idx <= '0;
                end

                S_FILL_LATCH: begin
                    if (latched < wr_total) begin
                        mem[wr_idx] <= sram_rdata;
                        wr_idx <= wr_idx + 1'b1;
                        latched <= latched + 1'b1;
                        cur_sram_addr <= cur_sram_addr + 'd4;
                    end
                end

                S_FULL: begin
                    rd_idx <= '0;
                    bias_idx <= '0;
                end

                S_PRIME: begin
                    filter_data_q <= repack_filter_word(32'd0);
                end

                S_READING: begin
                    if (filter_ready) begin
                        if (rd_idx + 1'b1 < filter_words_total_l) begin
                            filter_data_q <= repack_filter_word(rd_idx + 1'b1);
                        end
                        rd_idx <= rd_idx + 1'b1;
                    end
                    if (bias_valid && bias_ready) begin
                        bias_idx <= bias_idx + 16'd1;
                    end
                end

                default: ;
            endcase
        end
    end

    assign sram_en   = ((state == S_FILL_ISSUE) || (state == S_FILL_LATCH))
                     && (latched < wr_total);
    assign sram_addr = cur_sram_addr;

    assign filter_data  = filter_data_q;
    assign filter_valid = (state == S_READING);

    always_comb begin
        bias_word_w = repack_bias_word(bias_idx);
    end

    assign bias_word  = bias_word_w;
    assign bias_valid = (state == S_READING) && bias_en_l && (bias_idx < out_c_l);

    assign fill_done = (state == S_FULL) || (state == S_PRIME) || (state == S_READING);

endmodule
