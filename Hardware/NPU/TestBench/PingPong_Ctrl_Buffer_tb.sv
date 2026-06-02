`timescale 1ns/1ps
`include "define.svh"

module PingPong_Ctrl_Buffer_tb;
    localparam logic [1:0] EXEC_CONV = 2'd0;

    localparam int S_IDLE      = 0;
    localparam int S_LOAD_WGT  = 1;
    localparam int S_PE_CONFIG = 2;
    localparam int S_FILTER    = 3;
    localparam int S_IFMAP     = 4;
    localparam int S_IPSUM     = 5;
    localparam int S_OPSUM     = 6;
    localparam int S_DRAIN     = 8;
    localparam int S_DONE      = 9;

    localparam int MEM_WORDS = 8192;
    localparam int MEM_AW = 13;

    localparam logic [15:0] T_IN_H   = 16'd5;
    localparam logic [15:0] T_IN_W   = 16'd5;
    localparam logic [15:0] T_IN_C   = 16'd4;
    localparam logic [15:0] T_OUT_C  = 16'd8;
    localparam logic [3:0]  T_STRIDE = 4'd1;
    localparam logic [3:0]  T_PAD    = 4'd1;
    localparam logic [3:0]  T_KERNEL = 4'd3;

    localparam logic [31:0] T_IN_ADDR  = 32'h0000_0000;
    localparam logic [31:0] T_WGT_ADDR = 32'h0000_1000;
    localparam logic [31:0] T_OUT_ADDR = 32'h0000_2000;
    localparam logic [11:0] T_FLAGS    = 12'h00b;

    localparam int EXP_OUT_H       = 5;
    localparam int EXP_OUT_W       = 5;
    localparam int EXP_RAW_WEIGHT_B = 8 * 4 * 3 * 3;
    localparam int EXP_PARAM_B      = EXP_RAW_WEIGHT_B + 8 * 4;
    localparam int EXP_PARAM_W      = EXP_PARAM_B / 4;
    localparam int EXP_FILTER_W     = 8 * 3 * 3;
    localparam int EXP_INPUT_B     = 4 * 5 * 5;
    localparam int EXP_INPUT_W     = EXP_INPUT_B / 4;
    localparam int EXP_LINE_W      = EXP_OUT_H * EXP_OUT_W * 3 * 3;
    localparam int EXP_OUTPUT_B    = 8 * 5 * 5;
    localparam int EXP_OUTPUT_W    = EXP_OUTPUT_B / 4;
    localparam int EXP_OUTPUT_ELEM = 8 * 5 * 5;

    logic clk;
    logic rst;

    logic         exec_valid;
    logic [1:0]   exec_op;
    logic [15:0]  exec_in_h, exec_in_w, exec_in_c, exec_out_c;
    logic [31:0]  exec_in_addr, exec_wgt_addr, exec_out_addr;
    logic [11:0]  exec_flags;
    logic [3:0]   exec_stride, exec_pad, exec_kernel;
    logic [9:0]   exec_pconfig;
    logic [5:0]   exec_shift, exec_lhs_shift, exec_rhs_shift;
    logic         exec_done;

    logic         wb_fill_start;
    logic [`SRAM_ADDR_BITS-1:0] wb_fill_addr;
    logic [31:0]  wb_fill_bytes;
    logic         wb_fill_done;
    logic         wb_sel;

    logic         iob_in_start;
    logic [`SRAM_ADDR_BITS-1:0] iob_in_addr;
    logic [31:0]  iob_in_len;
    logic         iob_in_done;
    logic         iob_out_start;
    logic [`SRAM_ADDR_BITS-1:0] iob_out_addr;
    logic [31:0]  iob_out_len;
    logic         iob_out_done;
    logic         iob_swap;

    logic         lb_flush;
    logic [15:0]  lb_row_width;
    logic [3:0]   lb_kernel;
    logic         pe_tile_start;
    logic         cfg_done;

    logic [`CONFIG_SIZE-1:0] pe_config;
    logic [1:0]   glb_sel;
    logic [`XID_BITS-1:0] ifmap_tag_X, filter_tag_X, ipsum_tag_X, opsum_tag_X;
    logic [`YID_BITS-1:0] ifmap_tag_Y, filter_tag_Y, ipsum_tag_Y, opsum_tag_Y;
    logic         glb_ifmap_ready;
    logic         glb_ifmap_valid;
    logic         glb_filter_ready;
    logic         glb_filter_valid;
    logic         glb_ipsum_ready;
    logic         glb_opsum_valid;
    logic         glb_opsum_ready;
    logic         pp_ipsum_valid;
    logic         ifmap_en;

    logic [5:0]   ppu_shift;
    logic         ppu_silu_en;
    logic         ppu_maxpool_en;
    logic         ppu_maxpool_init;

    logic         oc_layer_start;
    logic         oc_bias_en;
    logic         oc_pixel_init;
    logic         oc_pixel_last;
    logic         oc_layer_last;
    logic [3:0]   oc_lane_sel;

    logic         add_en;
    logic [5:0]   add_lhs_shift;
    logic [5:0]   add_rhs_shift;
    logic         oc_done;

    logic         wb_sram_en;
    logic [`SRAM_ADDR_BITS-1:0] wb_sram_addr;
    logic [`DATA_BITS-1:0] wb_filter_data;
    logic         wb_filter_valid;
    logic         wb_filter_ready;

    logic         iob_rd_sram_en;
    logic         iob_rd_sram_we;
    logic [`SRAM_ADDR_BITS-1:0] iob_rd_sram_addr;
    logic [`DATA_BITS-1:0] iob_rd_sram_wdata;
    logic [`DATA_BITS-1:0] iob_ifmap_data;
    logic         iob_ifmap_valid;
    logic         iob_ifmap_ready;

    logic         iob_wr_sram_en;
    logic         iob_wr_sram_we;
    logic [`SRAM_ADDR_BITS-1:0] iob_wr_sram_addr;
    logic [`DATA_BITS-1:0] iob_wr_sram_wdata;
    logic [`DATA_BITS-1:0] iob_ppu_data;
    logic         iob_ppu_valid;
    logic         iob_ppu_ready;

    logic [`DATA_BITS-1:0] lb_win_data;
    logic         lb_done;
    logic         lb_win_valid;
    logic         lb_win_ready;

    logic         sram_en;
    logic         sram_we;
    logic [`SRAM_ADDR_BITS-1:0] sram_addr;
    logic [`DATA_BITS-1:0] sram_wdata;
    logic [`DATA_BITS-1:0] sram_rdata;
    logic [`DATA_BITS-1:0] mem [0:MEM_WORDS-1];
    logic [MEM_AW-1:0] sram_word_idx;

    int cycle;
    int state_last;
    int wb_fill_start_count;
    int iob_in_start_count;
    int iob_out_start_count;
    int lb_flush_count;
    int wb_sram_read_count;
    int iob_input_accept_count;
    int lb_window_accept_count;
    int filter_accept_count;
    int ifmap_accept_count;
    int ipsum_accept_count;
    int opsum_accept_count;
    int output_write_count;
    int oc_layer_start_count;
    int oc_layer_last_count;
    int pe_tile_start_count;
    int exec_done_count;
    int drain_wait;
    logic iob_out_done_seen;

    PingPong_Ctrl dut (
        .clk(clk), .rst(rst),
        .exec_valid(exec_valid), .exec_op(exec_op),
        .exec_in_h(exec_in_h), .exec_in_w(exec_in_w),
        .exec_in_c(exec_in_c), .exec_out_c(exec_out_c),
        .exec_in_addr(exec_in_addr), .exec_wgt_addr(exec_wgt_addr),
        .exec_out_addr(exec_out_addr),
        .exec_flags(exec_flags),
        .exec_stride(exec_stride), .exec_pad(exec_pad), .exec_kernel(exec_kernel),
        .exec_pconfig(exec_pconfig),
        .exec_shift(exec_shift),
        .exec_lhs_shift(exec_lhs_shift), .exec_rhs_shift(exec_rhs_shift),
        .exec_done(exec_done),
        .wb_fill_start(wb_fill_start), .wb_fill_addr(wb_fill_addr),
        .wb_fill_bytes(wb_fill_bytes), .wb_fill_done(wb_fill_done),
        .wb_sel(wb_sel),
        .iob_in_start(iob_in_start), .iob_in_addr(iob_in_addr),
        .iob_in_len(iob_in_len), .iob_in_done(iob_in_done),
        .iob_out_start(iob_out_start), .iob_out_addr(iob_out_addr),
        .iob_out_len(iob_out_len), .iob_out_done(iob_out_done),
        .iob_swap(iob_swap),
        .lb_flush(lb_flush), .lb_row_width(lb_row_width), .lb_kernel(lb_kernel),
        .pe_tile_start(pe_tile_start),
        .cfg_done(cfg_done),
        .pe_config(pe_config), .glb_sel(glb_sel),
        .ifmap_tag_X(ifmap_tag_X), .filter_tag_X(filter_tag_X),
        .ipsum_tag_X(ipsum_tag_X), .opsum_tag_X(opsum_tag_X),
        .ifmap_tag_Y(ifmap_tag_Y), .filter_tag_Y(filter_tag_Y),
        .ipsum_tag_Y(ipsum_tag_Y), .opsum_tag_Y(opsum_tag_Y),
        .glb_ifmap_ready(glb_ifmap_ready),
        .glb_ifmap_valid(glb_ifmap_valid),
        .glb_filter_ready(glb_filter_ready),
        .glb_filter_valid(glb_filter_valid),
        .glb_ipsum_ready(glb_ipsum_ready),
        .glb_opsum_valid(glb_opsum_valid),
        .glb_opsum_ready(glb_opsum_ready),
        .pp_ipsum_valid(pp_ipsum_valid),
        .ifmap_en(ifmap_en),
        .ppu_shift(ppu_shift),
        .ppu_silu_en(ppu_silu_en),
        .ppu_maxpool_en(ppu_maxpool_en),
        .ppu_maxpool_init(ppu_maxpool_init),
        .oc_layer_start(oc_layer_start),
        .oc_bias_en(oc_bias_en),
        .oc_pixel_init(oc_pixel_init),
        .oc_pixel_last(oc_pixel_last),
        .oc_layer_last(oc_layer_last),
        .oc_lane_sel(oc_lane_sel),
        .add_en(add_en),
        .add_lhs_shift(add_lhs_shift),
        .add_rhs_shift(add_rhs_shift),
        .oc_done(oc_done)
    );

    Weight_Buffer wb (
        .clk(clk), .rst(rst),
        .fill_start(wb_fill_start),
        .fill_addr(wb_fill_addr),
        .fill_bytes(wb_fill_bytes),
        .in_c(T_IN_C),
        .out_c(T_OUT_C),
        .kernel(T_KERNEL),
        .bias_en(T_FLAGS[`FLAG_BIAS]),
        .fill_done(wb_fill_done),
        .sram_en(wb_sram_en),
        .sram_addr(wb_sram_addr),
        .sram_rdata(sram_rdata),
        .filter_data(wb_filter_data),
        .filter_valid(wb_filter_valid),
        .filter_ready(wb_filter_ready),
        .bias_valid(),
        .bias_word(),
        .bias_ready(1'b0)
    );

    IOMap_Buffer iob_in (
        .clk(clk), .rst(rst),
        .mode_write(1'b0),
        .start(iob_in_start),
        .base_addr(iob_in_addr),
        .length(iob_in_len),
        .pack_nchw_read(1'b0),
        .unpack_nchw_write(1'b0),
        .tensor_c(T_IN_C),
        .tensor_h(T_IN_H),
        .tensor_w(T_IN_W),
        .done(iob_in_done),
        .sram_en(iob_rd_sram_en),
        .sram_we(iob_rd_sram_we),
        .sram_addr(iob_rd_sram_addr),
        .sram_wdata(iob_rd_sram_wdata),
        .sram_rdata(sram_rdata),
        .ifmap_data(iob_ifmap_data),
        .ifmap_valid(iob_ifmap_valid),
        .ifmap_ready(iob_ifmap_ready),
        .ppu_data('0),
        .ppu_valid(1'b0),
        .ppu_ready()
    );

    IOMap_Buffer iob_out (
        .clk(clk), .rst(rst),
        .mode_write(1'b1),
        .start(iob_out_start),
        .base_addr(iob_out_addr),
        .length(iob_out_len),
        .pack_nchw_read(1'b0),
        .unpack_nchw_write(1'b0),
        .tensor_c(T_OUT_C),
        .tensor_h(EXP_OUT_H[15:0]),
        .tensor_w(EXP_OUT_W[15:0]),
        .done(iob_out_done),
        .sram_en(iob_wr_sram_en),
        .sram_we(iob_wr_sram_we),
        .sram_addr(iob_wr_sram_addr),
        .sram_wdata(iob_wr_sram_wdata),
        .sram_rdata(sram_rdata),
        .ifmap_data(),
        .ifmap_valid(),
        .ifmap_ready(1'b0),
        .ppu_data(iob_ppu_data),
        .ppu_valid(iob_ppu_valid),
        .ppu_ready(iob_ppu_ready)
    );

    Line_Buffer lb (
        .clk(clk), .rst(rst),
        .layer_start(lb_flush),
        .in_h(T_IN_H),
        .in_w(T_IN_W),
        .out_h(EXP_OUT_H[15:0]),
        .kernel(T_KERNEL),
        .stride(T_STRIDE),
        .pad(T_PAD),
        .done(lb_done),
        .ifmap_data(iob_ifmap_data),
        .ifmap_valid(iob_ifmap_valid),
        .ifmap_ready(iob_ifmap_ready),
        .win_data(lb_win_data),
        .win_valid(lb_win_valid),
        .win_ready(lb_win_ready)
    );

    always #5 clk = ~clk;

    assign glb_filter_valid = wb_filter_valid;
    assign wb_filter_ready  = glb_filter_ready && (glb_sel == 2'd1);

    assign glb_ifmap_valid = lb_win_valid && ifmap_en;
    assign lb_win_ready    = glb_ifmap_ready && ifmap_en;

    assign glb_opsum_ready = 1'b1;
    assign glb_filter_ready = ((cycle % 5) != 1);
    assign glb_ifmap_ready  = ((cycle % 7) != 2);
    assign glb_ipsum_ready  = ((cycle % 3) != 1);
    assign glb_opsum_valid  = (dut.state == S_OPSUM) && ((cycle % 4) != 0);

    assign iob_ppu_valid = iob_ppu_ready && (dut.state == S_OPSUM) && ((cycle % 6) != 3);
    assign iob_ppu_data  = 32'hca00_0000 | output_write_count[15:0];

    always_comb begin
        sram_en    = 1'b0;
        sram_we    = 1'b0;
        sram_addr  = '0;
        sram_wdata = '0;
        if (wb_sram_en) begin
            sram_en   = 1'b1;
            sram_addr = wb_sram_addr;
        end else if (iob_rd_sram_en) begin
            sram_en   = 1'b1;
            sram_addr = iob_rd_sram_addr;
        end else if (iob_wr_sram_en) begin
            sram_en    = 1'b1;
            sram_we    = iob_wr_sram_we;
            sram_addr  = iob_wr_sram_addr;
            sram_wdata = iob_wr_sram_wdata;
        end
    end

    assign sram_word_idx = sram_addr[MEM_AW+1:2];

    always @(posedge clk) begin
        if (sram_en) begin
            if (sram_we) mem[sram_word_idx] <= sram_wdata;
            sram_rdata <= mem[sram_word_idx];
        end
    end

    initial begin
        for (int i = 0; i < MEM_WORDS; i++) begin
            mem[i] = 32'h1000_0000 + i[31:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
            state_last <= S_IDLE;
            wb_fill_start_count <= 0;
            iob_in_start_count <= 0;
            iob_out_start_count <= 0;
            lb_flush_count <= 0;
            wb_sram_read_count <= 0;
            iob_input_accept_count <= 0;
            lb_window_accept_count <= 0;
            filter_accept_count <= 0;
            ifmap_accept_count <= 0;
            ipsum_accept_count <= 0;
            opsum_accept_count <= 0;
            output_write_count <= 0;
            oc_layer_start_count <= 0;
            oc_layer_last_count <= 0;
            pe_tile_start_count <= 0;
            exec_done_count <= 0;
            drain_wait <= 0;
            iob_out_done_seen <= 1'b0;
            oc_done <= 1'b0;
        end else begin
            cycle <= cycle + 1;
            oc_done <= 1'b0;

            if (dut.state != state_last) begin
                $display("[MON][%0t] state %0d -> %0d", $time, state_last, dut.state);
                state_last <= dut.state;
            end

            if (wb_fill_start) begin
                wb_fill_start_count <= wb_fill_start_count + 1;
                $display("[MON][%0t] wb_fill_start addr=0x%08h bytes=%0d",
                         $time, wb_fill_addr, wb_fill_bytes);
            end
            if (iob_in_start) begin
                iob_in_start_count <= iob_in_start_count + 1;
                $display("[MON][%0t] iob_in_start addr=0x%08h bytes=%0d",
                         $time, iob_in_addr, iob_in_len);
            end
            if (iob_out_start) begin
                iob_out_start_count <= iob_out_start_count + 1;
                $display("[MON][%0t] iob_out_start addr=0x%08h bytes=%0d",
                         $time, iob_out_addr, iob_out_len);
            end
            if (lb_flush) begin
                lb_flush_count <= lb_flush_count + 1;
                $display("[MON][%0t] lb_flush row_width=%0d kernel=%0d",
                         $time, lb_row_width, lb_kernel);
            end

            if (wb_sram_en) wb_sram_read_count <= wb_sram_read_count + 1;
            if (iob_ifmap_valid && iob_ifmap_ready) iob_input_accept_count <= iob_input_accept_count + 1;
            if (glb_filter_valid && glb_filter_ready && dut.state == S_FILTER) filter_accept_count <= filter_accept_count + 1;
            if (glb_ifmap_valid && glb_ifmap_ready && dut.state == S_IFMAP) begin
                ifmap_accept_count <= ifmap_accept_count + 1;
                lb_window_accept_count <= lb_window_accept_count + 1;
            end
            if (pp_ipsum_valid && glb_ipsum_ready && dut.state == S_IPSUM) ipsum_accept_count <= ipsum_accept_count + 1;
            if (glb_opsum_valid && glb_opsum_ready && dut.state == S_OPSUM) opsum_accept_count <= opsum_accept_count + 1;
            if (iob_wr_sram_en && iob_wr_sram_we) output_write_count <= output_write_count + 1;
            if (oc_layer_start) oc_layer_start_count <= oc_layer_start_count + 1;
            if (oc_layer_last) oc_layer_last_count <= oc_layer_last_count + 1;
            if (pe_tile_start) pe_tile_start_count <= pe_tile_start_count + 1;
            if (exec_done) exec_done_count <= exec_done_count + 1;
            if (iob_out_done) iob_out_done_seen <= 1'b1;

            if (dut.state == S_DRAIN) begin
                if (iob_out_done_seen || iob_out_done) begin
                    drain_wait <= drain_wait + 1;
                    if (drain_wait == 2) begin
                        oc_done <= 1'b1;
                        $display("[MON][%0t] oc_done pulse after output buffer done", $time);
                    end
                end
            end else begin
                drain_wait <= 0;
            end

            if (cycle > 5000) begin
                $fatal(1, "[FAIL] timeout state=%0d filter=%0d ifmap=%0d ipsum=%0d opsum=%0d",
                       dut.state, filter_accept_count, ifmap_accept_count,
                       ipsum_accept_count, opsum_accept_count);
            end
        end
    end

    task automatic expect_eq(input string name, input int got, input int exp);
        if (got !== exp) begin
            $fatal(1, "[FAIL] %s got=%0d exp=%0d", name, got, exp);
        end
        $display("[CHECK] %s = %0d", name, got);
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        cfg_done = 1'b0;
        exec_valid = 1'b0;
        exec_op = EXEC_CONV;
        exec_in_h = T_IN_H;
        exec_in_w = T_IN_W;
        exec_in_c = T_IN_C;
        exec_out_c = T_OUT_C;
        exec_in_addr = T_IN_ADDR;
        exec_wgt_addr = T_WGT_ADDR;
        exec_out_addr = T_OUT_ADDR;
        exec_flags = T_FLAGS;
        exec_stride = T_STRIDE;
        exec_pad = T_PAD;
        exec_kernel = T_KERNEL;
        exec_pconfig = 10'h155;
        exec_shift = 6'd4;
        exec_lhs_shift = 6'd0;
        exec_rhs_shift = 6'd0;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        cfg_done = 1'b1;
        @(posedge clk);
        exec_valid = 1'b1;
        @(posedge clk);
        exec_valid = 1'b0;

        wait (exec_done_count == 1);
        repeat (2) @(posedge clk);

        expect_eq("wb_fill_start_count", wb_fill_start_count, 1);
        expect_eq("iob_in_start_count", iob_in_start_count, 1);
        expect_eq("iob_out_start_count", iob_out_start_count, 1);
        expect_eq("lb_flush_count", lb_flush_count, 1);
        expect_eq("wb_sram_read_count", wb_sram_read_count, EXP_PARAM_W * 2);
        expect_eq("iob_input_accept_count", iob_input_accept_count, EXP_INPUT_W);
        expect_eq("filter_accept_count", filter_accept_count, EXP_FILTER_W);
        expect_eq("ifmap_accept_count", ifmap_accept_count, EXP_LINE_W);
        expect_eq("lb_window_accept_count", lb_window_accept_count, EXP_LINE_W);
        expect_eq("ipsum_accept_count", ipsum_accept_count, EXP_OUTPUT_ELEM);
        expect_eq("opsum_accept_count", opsum_accept_count, EXP_OUTPUT_ELEM);
        expect_eq("output_write_count", output_write_count, EXP_OUTPUT_W);
        expect_eq("oc_layer_start_count", oc_layer_start_count, 1);
        expect_eq("oc_layer_last_count", oc_layer_last_count, 1);
        expect_eq("pe_tile_start_count", pe_tile_start_count, 24);
        expect_eq("exec_done_count", exec_done_count, 1);

        if (wb_fill_bytes !== EXP_PARAM_B[31:0]) $fatal(1, "[FAIL] wb_fill_bytes final mismatch");
        if (iob_in_len !== EXP_INPUT_B[31:0]) $fatal(1, "[FAIL] iob_in_len final mismatch");
        if (iob_out_len !== EXP_OUTPUT_B[31:0]) $fatal(1, "[FAIL] iob_out_len final mismatch");
        if (!ppu_silu_en) $fatal(1, "[FAIL] ppu_silu_en should be 1 for flags 0x00b");
        if (!oc_bias_en) $fatal(1, "[FAIL] oc_bias_en should be 1 for flags 0x00b");
        if (add_en) $fatal(1, "[FAIL] add_en should be 0 for CONV");

        $display("== PingPong_Ctrl_Buffer_tb PASS ==");
        $finish;
    end
endmodule
