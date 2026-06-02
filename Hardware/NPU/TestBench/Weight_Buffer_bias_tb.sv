`timescale 1ns/1ps
`include "define.svh"

module Weight_Buffer_bias_tb;
    localparam logic [`SRAM_ADDR_BITS-1:0] BASE = 22'h380000;
    localparam int PARAM_BYTES = 16 * 3 * 3 * 3 + 16 * 4;
    localparam int PARAM_WORDS = PARAM_BYTES / 4;

    logic clk = 1'b0;
    logic rst;
    logic fill_start;
    logic fill_done;
    logic sram_en;
    logic [`SRAM_ADDR_BITS-1:0] sram_addr;
    logic [`DATA_BITS-1:0] sram_rdata;
    logic [`DATA_BITS-1:0] filter_data;
    logic filter_valid;
    logic bias_valid;
    logic signed [`PSUM_BITS-1:0] bias_word;
    logic bias_ready;

    logic [`DATA_BITS-1:0] mem [0:PARAM_WORDS-1];
    byte unsigned raw [0:PARAM_BYTES-1];
    int expected [0:15];

    Weight_Buffer dut (
        .clk(clk), .rst(rst),
        .fill_start(fill_start),
        .fill_addr(BASE),
        .fill_bytes(PARAM_BYTES[31:0]),
        .in_c(16'd3),
        .out_c(16'd16),
        .kernel(4'd3),
        .bias_en(1'b1),
        .fill_done(fill_done),
        .sram_en(sram_en),
        .sram_addr(sram_addr),
        .sram_rdata(sram_rdata),
        .filter_data(filter_data),
        .filter_valid(filter_valid),
        .filter_ready(1'b0),
        .bias_valid(bias_valid),
        .bias_word(bias_word),
        .bias_ready(bias_ready)
    );

    always #5 clk = ~clk;

    always_comb begin
        if (sram_en) sram_rdata = mem[(sram_addr - BASE) >> 2];
        else         sram_rdata = '0;
    end

    initial begin
        int fd;
        int nread;
        int bias_base;

        fd = $fopen("../../../Build/weights.bin", "rb");
        if (fd == 0) $fatal(1, "Cannot open ../../../Build/weights.bin");
        nread = $fread(raw, fd);
        $fclose(fd);
        if (nread < PARAM_BYTES) $fatal(1, "weights too small: %0d", nread);

        for (int i = 0; i < PARAM_WORDS; i++) begin
            mem[i] = {raw[i*4 + 3], raw[i*4 + 2], raw[i*4 + 1], raw[i*4]};
        end

        bias_base = 16 * 3 * 3 * 3;
        for (int i = 0; i < 16; i++) begin
            expected[i] = int'({raw[bias_base + i*4 + 3],
                                raw[bias_base + i*4 + 2],
                                raw[bias_base + i*4 + 1],
                                raw[bias_base + i*4]});
        end

        rst = 1'b1;
        fill_start = 1'b0;
        bias_ready = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        fill_start = 1'b1;
        @(posedge clk);
        fill_start = 1'b0;

        wait (fill_done);
        @(posedge clk);
        bias_ready = 1'b1;

        for (int i = 0; i < 16; i++) begin
            wait (bias_valid === 1'b1);
            if (bias_word !== expected[i]) begin
                $fatal(1, "bias[%0d] got=%0d 0x%08h exp=%0d 0x%08h",
                       i, bias_word, bias_word, expected[i], expected[i]);
            end
            $display("[CHECK] bias[%0d] = %0d 0x%08h", i, bias_word, bias_word);
            @(posedge clk);
            #1;
        end

        $display("== Weight_Buffer_bias_tb PASS ==");
        $finish;
    end
endmodule
