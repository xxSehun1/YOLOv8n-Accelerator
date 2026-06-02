`timescale 1ns/1ps
`include "define.svh"

module LineBuffer_PE_pipeline_tb;
    localparam int LB_IN_H = 3;
    localparam int LB_IN_W = 4;
    localparam int LB_OUT_H = 3;
    localparam int LB_KERNEL = 3;
    localparam int LB_STRIDE = 1;
    localparam int LB_PAD = 1;
    localparam int LB_OUT_W = 4;
    localparam int LB_TOTAL_IN = LB_IN_H * LB_IN_W;
    localparam int LB_TOTAL_OUT = LB_OUT_H * LB_OUT_W * LB_KERNEL * LB_KERNEL;

    logic clk;
    logic rst;

    logic lb_start;
    logic [`DATA_BITS-1:0] lb_ifmap_data;
    logic lb_ifmap_valid;
    logic lb_ifmap_ready;
    logic [`DATA_BITS-1:0] lb_win_data;
    logic lb_win_valid;
    logic lb_win_ready;
    logic lb_done;

    int cycle;
    int lb_src_idx;
    int lb_cap_idx;
    int lb_error_count;

    Line_Buffer #(.MAX_WIDTH(16)) lb (
        .clk(clk),
        .rst(rst),
        .layer_start(lb_start),
        .in_h(LB_IN_H[15:0]),
        .in_w(LB_IN_W[15:0]),
        .out_h(LB_OUT_H[15:0]),
        .kernel(LB_KERNEL[3:0]),
        .stride(LB_STRIDE[3:0]),
        .pad(LB_PAD[3:0]),
        .done(lb_done),
        .ifmap_data(lb_ifmap_data),
        .ifmap_valid(lb_ifmap_valid),
        .ifmap_ready(lb_ifmap_ready),
        .win_data(lb_win_data),
        .win_valid(lb_win_valid),
        .win_ready(lb_win_ready)
    );

    logic pe_rst;
    logic pe_en;
    logic [`CONFIG_SIZE-1:0] pe_config;
    logic [`DATA_BITS-1:0] pe_ifmap;
    logic [`DATA_BITS-1:0] pe_filter;
    logic [`DATA_BITS-1:0] pe_ipsum;
    logic pe_ifmap_valid;
    logic pe_filter_valid;
    logic pe_ipsum_valid;
    logic pe_opsum_ready;
    logic [`DATA_BITS-1:0] pe_opsum;
    logic pe_ifmap_ready;
    logic pe_filter_ready;
    logic pe_ipsum_ready;
    logic pe_opsum_valid;

    PE pe (
        .clk(clk),
        .rst(pe_rst),
        .PE_en(pe_en),
        .tile_start(1'b0),
        .i_config(pe_config),
        .ifmap(pe_ifmap),
        .filter(pe_filter),
        .ipsum(pe_ipsum),
        .ifmap_valid(pe_ifmap_valid),
        .filter_valid(pe_filter_valid),
        .ipsum_valid(pe_ipsum_valid),
        .opsum_ready(pe_opsum_ready),
        .opsum(pe_opsum),
        .ifmap_ready(pe_ifmap_ready),
        .filter_ready(pe_filter_ready),
        .ipsum_ready(pe_ipsum_ready),
        .opsum_valid(pe_opsum_valid)
    );

    always #5 clk = ~clk;

    function automatic logic [`DATA_BITS-1:0] pix_word(input int y, input int x);
        pix_word = 32'h5500_0000 | ((y & 8'hff) << 8) | (x & 8'hff);
    endfunction

    function automatic logic [`DATA_BITS-1:0] lb_expected(input int idx);
        int oy;
        int rem;
        int ow;
        int tap_y;
        int tap_x;
        int in_y;
        int in_x;
        begin
            oy = idx / (LB_OUT_W * LB_KERNEL * LB_KERNEL);
            rem = idx % (LB_OUT_W * LB_KERNEL * LB_KERNEL);
            ow = rem / (LB_KERNEL * LB_KERNEL);
            rem = rem % (LB_KERNEL * LB_KERNEL);
            tap_y = rem / LB_KERNEL;
            tap_x = rem % LB_KERNEL;
            in_y = oy * LB_STRIDE - LB_PAD + tap_y;
            in_x = ow * LB_STRIDE - LB_PAD + tap_x;
            if (in_y < 0 || in_y >= LB_IN_H || in_x < 0 || in_x >= LB_IN_W)
                lb_expected = 32'h8080_8080;
            else
                lb_expected = pix_word(in_y, in_x);
        end
    endfunction

    function automatic logic [`DATA_BITS-1:0] pack4(
        input int b0,
        input int b1,
        input int b2,
        input int b3
    );
        pack4 = {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};
    endfunction

    function automatic logic signed [31:0] mac_ref3(
        input logic [31:0] w0,
        input logic [31:0] w1,
        input logic [31:0] w2,
        input logic [31:0] x0,
        input logic [31:0] x1,
        input logic [31:0] x2,
        input logic signed [31:0] ips
    );
        logic [31:0] w [0:2];
        logic [31:0] x [0:2];
        logic signed [31:0] acc;
        logic signed [8:0] sx;
        logic signed [7:0] sw;
        begin
            w[0] = w0; w[1] = w1; w[2] = w2;
            x[0] = x0; x[1] = x1; x[2] = x2;
            acc = ips;
            for (int i = 0; i < 3; i++) begin
                for (int j = 0; j < 4; j++) begin
                    sx = $signed({1'b0, x[i][j*8 +: 8]}) - 9'sd128;
                    sw = $signed(w[i][j*8 +: 8]);
                    acc = acc + sx * sw;
                end
            end
            mac_ref3 = acc;
        end
    endfunction

    task automatic expect_word(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got !== exp) begin
            $fatal(1, "[FAIL] %s got=0x%08h exp=0x%08h", name, got, exp);
        end
        $display("[CHECK] %s = 0x%08h", name, got);
    endtask

    task automatic expect_int(input string name, input int got, input int exp);
        if (got !== exp) begin
            $fatal(1, "[FAIL] %s got=%0d exp=%0d", name, got, exp);
        end
        $display("[CHECK] %s = %0d", name, got);
    endtask

    task automatic feed_filter(input logic [31:0] data);
        begin
            while (!pe_filter_ready) @(posedge clk);
            pe_filter = data;
            pe_filter_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            pe_filter_valid = 1'b0;
            pe_filter = '0;
        end
    endtask

    task automatic feed_ifmap(input logic [31:0] data);
        begin
            while (!pe_ifmap_ready) @(posedge clk);
            pe_ifmap = data;
            pe_ifmap_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            pe_ifmap_valid = 1'b0;
            pe_ifmap = '0;
        end
    endtask

    task automatic run_compute_check(
        input int out_idx,
        input logic [31:0] x0,
        input logic [31:0] x1,
        input logic [31:0] x2,
        input logic signed [31:0] ips,
        input logic [31:0] w0,
        input logic [31:0] w1,
        input logic [31:0] w2
    );
        logic signed [31:0] expected;
        logic signed [31:0] got;
        begin
            expected = mac_ref3(w0, w1, w2, x0, x1, x2, ips);
            while (!pe_ipsum_ready) @(posedge clk);
            pe_ipsum = ips;
            pe_ipsum_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            pe_ipsum_valid = 1'b0;
            pe_ipsum = '0;

            while (!pe_opsum_valid) @(posedge clk);
            got = $signed(pe_opsum);
            pe_opsum_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            pe_opsum_ready = 1'b0;

            if (got !== expected) begin
                $fatal(1, "[FAIL] PE opsum[%0d] got=%0d exp=%0d", out_idx, got, expected);
            end
            $display("[CHECK] PE opsum[%0d] = %0d", out_idx, got);
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
            lb_src_idx <= 0;
            lb_cap_idx <= 0;
            lb_error_count <= 0;
        end else begin
            cycle <= cycle + 1;

            if (lb_ifmap_valid && lb_ifmap_ready) begin
                lb_src_idx <= lb_src_idx + 1;
                $display("[MON][LB_IN][%0t] idx=%0d data=0x%08h",
                         $time, lb_src_idx, lb_ifmap_data);
            end

            if (lb_win_valid && lb_win_ready) begin
                if (lb_win_data !== lb_expected(lb_cap_idx)) begin
                    $display("[FAIL][LB_OUT][%0t] idx=%0d got=0x%08h exp=0x%08h",
                             $time, lb_cap_idx, lb_win_data, lb_expected(lb_cap_idx));
                    lb_error_count <= lb_error_count + 1;
                end else if (lb_cap_idx < 12 || lb_cap_idx >= LB_TOTAL_OUT - 6) begin
                    $display("[MON][LB_OUT][%0t] idx=%0d data=0x%08h",
                             $time, lb_cap_idx, lb_win_data);
                end
                lb_cap_idx <= lb_cap_idx + 1;
            end

            if (cycle > 3000) begin
                $fatal(1, "[FAIL] global timeout lb_src=%0d lb_cap=%0d", lb_src_idx, lb_cap_idx);
            end
        end
    end

    always_comb begin
        lb_ifmap_valid = (lb_src_idx < LB_TOTAL_IN);
        lb_ifmap_data = pix_word(lb_src_idx / LB_IN_W, lb_src_idx % LB_IN_W);
        lb_win_ready = ((cycle % 4) != 1);
    end

    initial begin
        logic [31:0] w0;
        logic [31:0] w1;
        logic [31:0] w2;
        logic [31:0] seq [0:6];

        clk = 1'b0;
        rst = 1'b1;
        pe_rst = 1'b1;
        lb_start = 1'b0;
        pe_en = 1'b0;
        pe_config = '0;
        pe_ifmap = '0;
        pe_filter = '0;
        pe_ipsum = '0;
        pe_ifmap_valid = 1'b0;
        pe_filter_valid = 1'b0;
        pe_ipsum_valid = 1'b0;
        pe_opsum_ready = 1'b0;

        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        lb_start = 1'b1;
        @(posedge clk);
        lb_start = 1'b0;

        wait (lb_done);
        repeat (2) @(posedge clk);
        expect_int("LineBuffer input accepts", lb_src_idx, LB_TOTAL_IN);
        expect_int("LineBuffer window accepts", lb_cap_idx, LB_TOTAL_OUT);
        expect_int("LineBuffer mismatch count", lb_error_count, 0);

        $display("[MON] Starting single PE pipeline check");
        pe_rst = 1'b1;
        repeat (3) @(posedge clk);
        pe_rst = 1'b0;
        @(negedge clk);
        pe_config = {9'd0, 5'd0, 4'd2, 4'd3, 10'd0}; // one OC, stride=2, kernel=3
        pe_en = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pe_en = 1'b0;

        w0 = pack4(1, -2, 3, -4);
        w1 = pack4(2, 1, -1, 3);
        w2 = pack4(-3, 4, 1, -2);

        feed_filter(w0);
        feed_filter(w1);
        feed_filter(w2);
        expect_word("PE w_buf[0][0]", pe.w_buf[0][0], w0);
        expect_word("PE w_buf[0][1]", pe.w_buf[0][1], w1);
        expect_word("PE w_buf[0][2]", pe.w_buf[0][2], w2);

        seq[0] = pack4(128, 128, 128, 128); // left pad
        seq[1] = pack4(129, 130, 131, 132);
        seq[2] = pack4(125, 126, 127, 128);
        seq[3] = pack4(140, 141, 142, 143);
        seq[4] = pack4(120, 119, 118, 117);
        seq[5] = pack4(135, 136, 137, 138);
        seq[6] = pack4(128, 128, 128, 128); // right pad

        feed_ifmap(seq[0]);
        feed_ifmap(seq[1]);
        feed_ifmap(seq[2]);
        expect_word("PE if_reg[0] first", pe.if_reg[0], seq[0]);
        expect_word("PE if_reg[1] first", pe.if_reg[1], seq[1]);
        expect_word("PE if_reg[2] first", pe.if_reg[2], seq[2]);
        run_compute_check(0, seq[0], seq[1], seq[2], 32'sd7, w0, w1, w2);

        feed_ifmap(seq[3]);
        feed_ifmap(seq[4]);
        expect_word("PE if_reg[0] stride2", pe.if_reg[0], seq[2]);
        expect_word("PE if_reg[1] stride2", pe.if_reg[1], seq[3]);
        expect_word("PE if_reg[2] stride2", pe.if_reg[2], seq[4]);
        run_compute_check(1, seq[2], seq[3], seq[4], -32'sd11, w0, w1, w2);

        feed_ifmap(seq[5]);
        feed_ifmap(seq[6]);
        expect_word("PE if_reg[0] right", pe.if_reg[0], seq[4]);
        expect_word("PE if_reg[1] right", pe.if_reg[1], seq[5]);
        expect_word("PE if_reg[2] right", pe.if_reg[2], seq[6]);
        run_compute_check(2, seq[4], seq[5], seq[6], 32'sd123, w0, w1, w2);

        $display("== LineBuffer_PE_pipeline_tb PASS ==");
        $finish;
    end
endmodule
