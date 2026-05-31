`timescale 1ns/1ps
`include "define.svh"

module NPU_ctrl_top_tb;
    localparam int CLK_HALF = 5;

    localparam logic [31:0] DRAM_INPUT_BASE  = 32'h0000_0000;
    localparam logic [31:0] DRAM_OUTPUT_BASE = 32'h0020_0000;
    localparam logic [31:0] DRAM_WEIGHT_BASE = 32'h0100_0000;

    localparam int INPUT_BYTES  = 32'h0012_C000;
    localparam int OUTPUT_BYTES = 32'h000A_F000;
    localparam int WEIGHT_BYTES = 2 * 1024 * 1024;

    localparam int INPUT_WORDS  = INPUT_BYTES  / 4;
    localparam int OUTPUT_WORDS = OUTPUT_BYTES / 4;
    localparam int WEIGHT_WORDS = WEIGHT_BYTES / 4;

    localparam int EXPECT_PC      = 127;
    localparam int EXPECT_CONV    = 27;
    localparam int EXPECT_POOL    = 3;
    localparam int EXPECT_ADD     = 6;
    localparam int EXPECT_EXEC    = EXPECT_CONV + EXPECT_POOL + EXPECT_ADD;
    localparam int EXPECT_WGT_LD  = 27;
    localparam int EXPECT_COPY    = 18;
    localparam int EXPECT_STORE   = 3;
    localparam int MONITOR_DMAS   = 16;
    localparam int MONITOR_EXECS  = 12;

    logic clk = 1'b0;
    logic rst;
    logic start;
    logic halted;

    logic dram_en;
    logic dram_we;
    logic [31:0]           dram_addr;
    logic [`DATA_BITS-1:0] dram_wdata;
    logic [`DATA_BITS-1:0] dram_rdata;

    logic [15:0] debug_pc;
    logic debug_instr_req, debug_instr_valid, debug_exec_valid, debug_dma_valid;
    logic [15:0] debug_exec_count, debug_conv_count, debug_pool_count, debug_add_count;
    logic debug_input_loaded;
    logic [15:0] debug_weight_load_count, debug_sram_copy_count, debug_store_count;
    int monitor_dma_seen = 0;
    int monitor_exec_seen = 0;
    bit concat_probe_armed = 1'b0;
    bit concat_probe_checked = 1'b0;
    logic [31:0] concat_probe_src;
    logic [31:0] concat_probe_dst;
    logic [`DATA_BITS-1:0] concat_probe_word;

    logic [`DATA_BITS-1:0] dram_in_mem  [0:INPUT_WORDS-1];
    logic [`DATA_BITS-1:0] dram_out_mem [0:OUTPUT_WORDS-1];
    logic [`DATA_BITS-1:0] dram_wgt_mem [0:WEIGHT_WORDS-1];
    byte unsigned weight_bytes [0:WEIGHT_BYTES-1];

    NPU_ctrl_top dut (
        .clk(clk), .rst(rst), .start(start), .halted(halted),
        .dram_en(dram_en), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata), .dram_rdata(dram_rdata),
        .debug_pc(debug_pc),
        .debug_instr_req(debug_instr_req),
        .debug_instr_valid(debug_instr_valid),
        .debug_exec_valid(debug_exec_valid),
        .debug_dma_valid(debug_dma_valid),
        .debug_exec_count(debug_exec_count),
        .debug_conv_count(debug_conv_count),
        .debug_pool_count(debug_pool_count),
        .debug_add_count(debug_add_count),
        .debug_input_loaded(debug_input_loaded),
        .debug_weight_load_count(debug_weight_load_count),
        .debug_sram_copy_count(debug_sram_copy_count),
        .debug_store_count(debug_store_count)
    );

    always #CLK_HALF clk = ~clk;

    function automatic bit in_input_region(input logic [31:0] addr);
        in_input_region = (addr >= DRAM_INPUT_BASE)
                       && (addr <  DRAM_INPUT_BASE + INPUT_BYTES);
    endfunction

    function automatic bit in_output_region(input logic [31:0] addr);
        in_output_region = (addr >= DRAM_OUTPUT_BASE)
                        && (addr <  DRAM_OUTPUT_BASE + OUTPUT_BYTES);
    endfunction

    function automatic bit in_weight_region(input logic [31:0] addr);
        in_weight_region = (addr >= DRAM_WEIGHT_BASE)
                        && (addr <  DRAM_WEIGHT_BASE + WEIGHT_BYTES);
    endfunction

    always @(posedge clk) begin
        if (dram_en) begin
            if (in_weight_region(dram_addr)) begin
                if (dram_we) begin
                    dram_wgt_mem[(dram_addr - DRAM_WEIGHT_BASE) >> 2] <= dram_wdata;
                end
                dram_rdata <= dram_wgt_mem[(dram_addr - DRAM_WEIGHT_BASE) >> 2];
            end else if (in_output_region(dram_addr)) begin
                if (dram_we) begin
                    dram_out_mem[(dram_addr - DRAM_OUTPUT_BASE) >> 2] <= dram_wdata;
                end
                dram_rdata <= dram_out_mem[(dram_addr - DRAM_OUTPUT_BASE) >> 2];
            end else if (in_input_region(dram_addr)) begin
                if (dram_we) begin
                    dram_in_mem[(dram_addr - DRAM_INPUT_BASE) >> 2] <= dram_wdata;
                end
                dram_rdata <= dram_in_mem[(dram_addr - DRAM_INPUT_BASE) >> 2];
            end else begin
                dram_rdata <= '0;
                if (dram_we) begin
                    $fatal(1, "Unexpected DRAM write addr=0x%08h data=0x%08h",
                           dram_addr, dram_wdata);
                end
            end
        end
    end

    function automatic string dma_kind;
        if (dut.i_dma.dma_is_store) begin
            dma_kind = "DMA_ST SRAM->DRAM";
        end else if (dut.i_dma.dma_dram >= DRAM_WEIGHT_BASE) begin
            dma_kind = "DMA_LD DRAM_WEIGHT->SRAM";
        end else if (!dut.i_dma.debug_input_loaded) begin
            dma_kind = "DMA_LD DRAM_INPUT->SRAM";
        end else begin
            dma_kind = "DMA_LD SRAM->SRAM concat-copy";
        end
    endfunction

    function automatic string exec_kind(input logic [1:0] op);
        case (op)
            2'd0: exec_kind = "CONV";
            2'd1: exec_kind = "POOL";
            2'd2: exec_kind = "ADD";
            default: exec_kind = "UNKNOWN";
        endcase
    endfunction

    always @(posedge clk) begin
        if (!rst && dut.i_dma.state == 2'd0 && dut.i_dma.dma_valid) begin
            monitor_dma_seen = monitor_dma_seen + 1;
            if (monitor_dma_seen <= MONITOR_DMAS
                || dut.i_dma.dma_is_store
                || (!dut.i_dma.dma_is_store && dut.i_dma.dma_dram < DRAM_WEIGHT_BASE
                    && dut.i_dma.debug_input_loaded)) begin
                $display("[DMA %0d][pc=%0d] %s dram/src=0x%08h sram/dst=0x%08h size=0x%08h",
                         monitor_dma_seen, debug_pc, dma_kind(),
                         dut.i_dma.dma_dram, dut.i_dma.dma_sram,
                         dut.i_dma.dma_size);
            end
            if (!concat_probe_armed
                && !dut.i_dma.dma_is_store
                && dut.i_dma.dma_dram < DRAM_WEIGHT_BASE
                && dut.i_dma.debug_input_loaded) begin
                concat_probe_armed = 1'b1;
                concat_probe_src = dut.i_dma.dma_dram;
                concat_probe_dst = dut.i_dma.dma_sram;
                concat_probe_word = dut.i_sram.mem[dut.i_dma.dma_dram >> 2];
                $display("[CHECKPOINT] concat probe armed src=0x%08h dst=0x%08h src_word=0x%08h",
                         dut.i_dma.dma_dram, dut.i_dma.dma_sram,
                         dut.i_sram.mem[dut.i_dma.dma_dram >> 2]);
            end
        end

        if (concat_probe_armed && !concat_probe_checked
            && dut.i_dma.state == 2'd3 && dut.i_dma.tr_src_sram) begin
            concat_probe_checked = 1'b1;
            if (dut.i_sram.mem[concat_probe_dst >> 2] !== concat_probe_word) begin
                $fatal(1, "Concat SRAM copy mismatch: src=0x%08h dst=0x%08h expect=0x%08h got=0x%08h",
                       concat_probe_src, concat_probe_dst, concat_probe_word,
                       dut.i_sram.mem[concat_probe_dst >> 2]);
            end
            $display("[CHECKPOINT] concat copy content matched at dst=0x%08h word=0x%08h",
                     concat_probe_dst, dut.i_sram.mem[concat_probe_dst >> 2]);
        end

        if (!rst && dut.i_dummy_exec.state == 2'd0
            && dut.i_dummy_exec.exec_valid) begin
            monitor_exec_seen = monitor_exec_seen + 1;
            if (monitor_exec_seen <= MONITOR_EXECS
                || dut.i_dummy_exec.exec_op != 2'd0) begin
                $display("[EXEC %0d][pc=%0d] %s out=0x%08h H=%0d W=%0d OC=%0d stride=%0d pad=%0d kernel=%0d",
                         monitor_exec_seen, debug_pc,
                         exec_kind(dut.i_dummy_exec.exec_op),
                         dut.i_dummy_exec.exec_out_addr,
                         dut.i_dummy_exec.exec_in_h,
                         dut.i_dummy_exec.exec_in_w,
                         dut.i_dummy_exec.exec_out_c,
                         dut.i_dummy_exec.exec_stride,
                         dut.i_dummy_exec.exec_pad,
                         dut.i_dummy_exec.exec_kernel);
            end
        end
    end

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $fatal(1, "CHECK FAILED: %s", message);
        end
        $display("  PASS: %s", message);
    endtask

    task automatic load_weights;
        int fd;
        int nread;
        begin
            fd = $fopen("../../../Build/weights.bin", "rb");
            if (fd == 0) begin
                $fatal(1, "Cannot open ../../../Build/weights.bin");
            end
            nread = $fread(weight_bytes, fd);
            $fclose(fd);
            $display("Loaded %0d weight bytes", nread);
            for (int i = 0; i < nread; i += 4) begin
                dram_wgt_mem[i >> 2] = {
                    (i + 3 < nread) ? weight_bytes[i + 3] : 8'h00,
                    (i + 2 < nread) ? weight_bytes[i + 2] : 8'h00,
                    (i + 1 < nread) ? weight_bytes[i + 1] : 8'h00,
                    weight_bytes[i]
                };
            end
        end
    endtask

    initial begin
        for (int i = 0; i < INPUT_WORDS; i++) begin
            dram_in_mem[i] = 32'h8080_8080 ^ i[31:0];
        end
        for (int i = 0; i < OUTPUT_WORDS; i++) begin
            dram_out_mem[i] = 32'h0000_0000;
        end
        for (int i = 0; i < WEIGHT_WORDS; i++) begin
            dram_wgt_mem[i] = 32'h0000_0000;
        end
        load_weights();
    end

    initial begin
        $display("== NPU_ctrl_top_tb: generated ISA control/data-exchange sim ==");
        $display("Requires npu_program.hex in this simulation cwd.");

        rst = 1'b1;
        start = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        $display("Start pulsed at %0t", $time);

        fork
            begin
                wait (halted === 1'b1);
                $display("HALTED at %0t", $time);
            end
            begin
                repeat (20_000_000) @(posedge clk);
                $fatal(1, "Timeout waiting for HALT. pc=%0d exec=%0d copy=%0d store=%0d",
                       debug_pc, debug_exec_count, debug_sram_copy_count,
                       debug_store_count);
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $display("== Checkpoints ==");
        $display("pc=%0d exec=%0d conv=%0d pool=%0d add=%0d",
                 debug_pc, debug_exec_count, debug_conv_count,
                 debug_pool_count, debug_add_count);
        $display("input_loaded=%0b weight_ld=%0d sram_copy=%0d store=%0d",
                 debug_input_loaded, debug_weight_load_count,
                 debug_sram_copy_count, debug_store_count);

        check(halted === 1'b1, "HALT reached");
        check(debug_pc == 16'(EXPECT_PC), "PC is parked at HALT instruction");
        check(debug_exec_count == 16'(EXPECT_EXEC), "all generated EXEC ops accepted");
        check(debug_conv_count == 16'(EXPECT_CONV), "CONV count matches generated ISA");
        check(debug_pool_count == 16'(EXPECT_POOL), "POOL count matches generated ISA");
        check(debug_add_count == 16'(EXPECT_ADD), "ADD count matches generated ISA");
        check(debug_input_loaded === 1'b1, "first DMA_LD classified as input DRAM load");
        check(debug_weight_load_count == 16'(EXPECT_WGT_LD), "weight DMA_LD count matches generated ISA");
        check(debug_sram_copy_count == 16'(EXPECT_COPY), "concat DMA_LD SRAM-copy count matches generated ISA");
        check(concat_probe_checked === 1'b1, "concat SRAM-copy content was checked");
        check(debug_store_count == 16'(EXPECT_STORE), "DMA_ST spill count matches generated ISA");

        check(!$isunknown(dram_out_mem[0]) && dram_out_mem[0] != 32'h0,
              "P3 output base received nonzero dummy data");
        check(!$isunknown(dram_out_mem[32'h0006_4000 >> 2])
              && dram_out_mem[32'h0006_4000 >> 2] != 32'h0,
              "P4 output base received nonzero dummy data");
        check(!$isunknown(dram_out_mem[32'h0009_6000 >> 2])
              && dram_out_mem[32'h0009_6000 >> 2] != 32'h0,
              "P5 output base received nonzero dummy data");

        $display("== NPU_ctrl_top_tb PASS ==");
        $finish;
    end

endmodule
