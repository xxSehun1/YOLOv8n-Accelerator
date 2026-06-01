`timescale 1ns/1ps
`include "define.svh"

module DMA_ctrl_unit_tb;
    localparam int CLK_HALF = 5;
    localparam int MEM_WORDS = 2048;
    localparam int TEST_WORDS = 16;
    localparam logic [31:0] OUT_BASE = `DRAM_OUTPUT_BASE;
    localparam logic [31:0] WGT_BASE = `DRAM_WEIGHT_BASE;

    logic clk = 1'b0;
    logic rst;

    logic         dma_valid;
    logic         dma_is_store;
    logic [31:0]  dma_dram;
    logic [31:0]  dma_sram;
    logic [31:0]  dma_size;
    logic         dma_done;

    logic         dram_en;
    logic         dram_we;
    logic [31:0]  dram_addr;
    logic [`DATA_BITS-1:0] dram_wdata;
    logic [`DATA_BITS-1:0] dram_rdata;

    logic         sram_en;
    logic         sram_we;
    logic [`SRAM_ADDR_BITS-1:0] sram_addr;
    logic [`DATA_BITS-1:0]      sram_wdata;
    logic [`DATA_BITS-1:0]      sram_rdata;

    logic        debug_input_loaded;
    logic [15:0] debug_weight_load_count;
    logic [15:0] debug_sram_copy_count;
    logic [15:0] debug_store_count;

    logic [`DATA_BITS-1:0] dram_mem [0:MEM_WORDS-1];
    logic [`DATA_BITS-1:0] sram_mem [0:MEM_WORDS-1];

    bit mon_active;
    bit mon_is_store;
    logic [31:0] mon_dram_base;
    logic [31:0] mon_sram_base;
    int mon_words;
    int dram_read_count, dram_write_count;
    int sram_read_count, sram_write_count;
    int done_count;

    DMA_ctrl dut (
        .clk(clk), .rst(rst),
        .dma_valid(dma_valid), .dma_is_store(dma_is_store),
        .dma_dram(dma_dram), .dma_sram(dma_sram), .dma_size(dma_size),
        .dma_done(dma_done),
        .dram_en(dram_en), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata), .dram_rdata(dram_rdata),
        .sram_en(sram_en), .sram_we(sram_we),
        .sram_addr(sram_addr), .sram_wdata(sram_wdata), .sram_rdata(sram_rdata),
        .debug_input_loaded(debug_input_loaded),
        .debug_weight_load_count(debug_weight_load_count),
        .debug_sram_copy_count(debug_sram_copy_count),
        .debug_store_count(debug_store_count)
    );

    always #CLK_HALF clk = ~clk;

    function automatic int dram_index(input logic [31:0] addr);
        if (addr >= WGT_BASE) begin
            dram_index = (addr - WGT_BASE) >> 2;
        end else if (addr >= OUT_BASE) begin
            dram_index = 512 + ((addr - OUT_BASE) >> 2);
        end else begin
            dram_index = 1024 + (addr >> 2);
        end
    endfunction

    function automatic int sram_index(input logic [31:0] addr);
        sram_index = addr >> 2;
    endfunction

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $fatal(1, "CHECK FAILED: %s", message);
        end
        $display("  PASS: %s", message);
    endtask

    always @(posedge clk) begin
        if (dram_en) begin
            int idx;
            idx = dram_index(dram_addr);
            if (idx < 0 || idx >= MEM_WORDS) begin
                $fatal(1, "DRAM index out of range addr=0x%08h idx=%0d", dram_addr, idx);
            end
            if (dram_we) begin
                dram_mem[idx] <= dram_wdata;
            end
            dram_rdata <= dram_mem[idx];
        end
    end

    always @(posedge clk) begin
        if (sram_en) begin
            int idx;
            idx = sram_index({10'd0, sram_addr});
            if (idx < 0 || idx >= MEM_WORDS) begin
                $fatal(1, "SRAM index out of range addr=0x%08h idx=%0d",
                       {10'd0, sram_addr}, idx);
            end
            if (sram_we) begin
                sram_mem[idx] <= sram_wdata;
            end
            sram_rdata <= sram_mem[idx];
        end
    end

    always @(posedge clk) begin
        if (!rst && mon_active) begin
            #1;
            if (dut.state == 2'd1) begin
                if (mon_is_store) begin
                    check(sram_en === 1'b1 && sram_we === 1'b0,
                          "DMA_ST S_RD reads SRAM");
                    check({10'd0, sram_addr} == mon_sram_base + (sram_read_count << 2),
                          "DMA_ST SRAM read address sequence");
                    sram_read_count++;
                end else begin
                    check(dram_en === 1'b1 && dram_we === 1'b0,
                          "DMA_LD S_RD reads DRAM");
                    check(dram_addr == mon_dram_base + (dram_read_count << 2),
                          "DMA_LD DRAM read address sequence");
                    dram_read_count++;
                end
            end else if (dut.state == 2'd2) begin
                if (mon_is_store) begin
                    check(dram_en === 1'b1 && dram_we === 1'b1,
                          "DMA_ST S_WR writes DRAM");
                    check(dram_addr == mon_dram_base + (dram_write_count << 2),
                          "DMA_ST DRAM write address sequence");
                    dram_write_count++;
                end else begin
                    check(sram_en === 1'b1 && sram_we === 1'b1,
                          "DMA_LD S_WR writes SRAM");
                    check({10'd0, sram_addr} == mon_sram_base + (sram_write_count << 2),
                          "DMA_LD SRAM write address sequence");
                    sram_write_count++;
                end
            end else if (dut.state == 2'd3) begin
                done_count++;
            end
        end
    end

    task automatic reset_dut;
        begin
            rst = 1'b1;
            dma_valid = 1'b0;
            dma_is_store = 1'b0;
            dma_dram = '0;
            dma_sram = '0;
            dma_size = '0;
            mon_active = 1'b0;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic init_memories;
        begin
            for (int i = 0; i < MEM_WORDS; i++) begin
                dram_mem[i] = 32'hD000_0000 ^ i[31:0];
                sram_mem[i] = 32'h5000_0000 ^ i[31:0];
            end
        end
    endtask

    task automatic start_transfer(
        input bit is_store,
        input logic [31:0] dram_base,
        input logic [31:0] sram_base,
        input int words
    );
        begin
            mon_is_store = is_store;
            mon_dram_base = dram_base;
            mon_sram_base = sram_base;
            mon_words = words;
            dram_read_count = 0;
            dram_write_count = 0;
            sram_read_count = 0;
            sram_write_count = 0;
            done_count = 0;
            mon_active = 1'b1;

            dma_is_store = is_store;
            dma_dram = dram_base;
            dma_sram = sram_base;
            dma_size = words * 4;
            dma_valid = 1'b1;

            wait (dma_done === 1'b1);
            #1;
            check(dut.widx == words, "DMA widx reached expected word count");
            dma_valid = 1'b0;
            @(posedge clk);
            #1;
            check(dut.state == 2'd0, "DMA returned to IDLE before next command");
            mon_active = 1'b0;
        end
    endtask

    task automatic check_ld_result(
        input string label,
        input logic [31:0] dram_base,
        input logic [31:0] sram_base,
        input int words
    );
        int mid;
        begin
            mid = words / 2;
            check(dram_read_count == words, {label, " DRAM read count"});
            check(sram_write_count == words, {label, " SRAM write count"});
            check(done_count == 1, {label, " dma_done single pulse"});
            check(sram_mem[sram_index(sram_base)] === dram_mem[dram_index(dram_base)],
                  {label, " first word copied"});
            check(sram_mem[sram_index(sram_base + (mid << 2))]
                  === dram_mem[dram_index(dram_base + (mid << 2))],
                  {label, " middle word copied"});
            check(sram_mem[sram_index(sram_base + ((words - 1) << 2))]
                  === dram_mem[dram_index(dram_base + ((words - 1) << 2))],
                  {label, " last word copied"});
        end
    endtask

    task automatic check_st_result(
        input string label,
        input logic [31:0] dram_base,
        input logic [31:0] sram_base,
        input int words
    );
        int mid;
        begin
            mid = words / 2;
            check(sram_read_count == words, {label, " SRAM read count"});
            check(dram_write_count == words, {label, " DRAM write count"});
            check(done_count == 1, {label, " dma_done single pulse"});
            check(dram_mem[dram_index(dram_base)] === sram_mem[sram_index(sram_base)],
                  {label, " first word copied"});
            check(dram_mem[dram_index(dram_base + (mid << 2))]
                  === sram_mem[sram_index(sram_base + (mid << 2))],
                  {label, " middle word copied"});
            check(dram_mem[dram_index(dram_base + ((words - 1) << 2))]
                  === sram_mem[sram_index(sram_base + ((words - 1) << 2))],
                  {label, " last word copied"});
        end
    endtask

    initial begin
        init_memories();
        reset_dut();

        $display("== DMA_ctrl_unit_tb: small DMA_LD ==");
        start_transfer(1'b0, 32'h0000_0040, 32'h0000_0100, TEST_WORDS);
        check_ld_result("small DMA_LD", 32'h0000_0040, 32'h0000_0100, TEST_WORDS);
        check(debug_input_loaded === 1'b1, "input/debug load flag set");
        check(debug_sram_copy_count == 16'd0, "no SRAM-copy overload counted");

        $display("== DMA_ctrl_unit_tb: small weight DMA_LD ==");
        start_transfer(1'b0, WGT_BASE + 32'h0000_0040, 32'h0000_0300, TEST_WORDS);
        check_ld_result("weight DMA_LD", WGT_BASE + 32'h0000_0040, 32'h0000_0300, TEST_WORDS);
        check(debug_weight_load_count == 16'd1, "weight load count incremented");
        check(debug_sram_copy_count == 16'd0, "weight load did not count as SRAM copy");

        $display("== DMA_ctrl_unit_tb: small DMA_ST ==");
        start_transfer(1'b1, OUT_BASE + 32'h0000_0080, 32'h0000_0200, TEST_WORDS);
        check_st_result("small DMA_ST", OUT_BASE + 32'h0000_0080, 32'h0000_0200, TEST_WORDS);
        check(debug_store_count == 16'd1, "store count incremented");

        $display("== DMA_ctrl_unit_tb: DRAM staging store/load pair ==");
        start_transfer(1'b1, OUT_BASE + 32'h0000_0100, 32'h0000_0400, TEST_WORDS);
        check_st_result("staging DMA_ST", OUT_BASE + 32'h0000_0100, 32'h0000_0400, TEST_WORDS);
        for (int i = 0; i < TEST_WORDS; i++) begin
            sram_mem[sram_index(32'h0000_0500 + (i << 2))] = 32'h0;
        end
        start_transfer(1'b0, OUT_BASE + 32'h0000_0100, 32'h0000_0500, TEST_WORDS);
        check_ld_result("staging DMA_LD", OUT_BASE + 32'h0000_0100, 32'h0000_0500, TEST_WORDS);
        for (int i = 0; i < TEST_WORDS; i++) begin
            check(sram_mem[sram_index(32'h0000_0500 + (i << 2))]
                  === sram_mem[sram_index(32'h0000_0400 + (i << 2))],
                  "staging SRAM source and reload destination match");
        end

        $display("== DMA_ctrl_unit_tb PASS ==");
        $finish;
    end

endmodule
