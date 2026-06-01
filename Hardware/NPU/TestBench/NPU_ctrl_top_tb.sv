`timescale 1ns/1ps
`include "define.svh"

module NPU_ctrl_top_tb;
    localparam int CLK_HALF = 5;

    localparam logic [31:0] DRAM_INPUT_BASE  = 32'h0000_0000;
    localparam logic [31:0] DRAM_OUTPUT_BASE = 32'h0020_0000;
    localparam logic [31:0] DRAM_WEIGHT_BASE = 32'h0100_0000;

    localparam int INPUT_BYTES  = 32'h0012_C000;
    localparam int OUTPUT_BYTES = 14 * 1024 * 1024;
    localparam int WEIGHT_BYTES = 2 * 1024 * 1024;

    localparam int INPUT_WORDS  = INPUT_BYTES  / 4;
    localparam int OUTPUT_WORDS = OUTPUT_BYTES / 4;
    localparam int WEIGHT_WORDS = WEIGHT_BYTES / 4;

    localparam int EXPECT_PC      = 141;
    localparam int EXPECT_CONV    = 27;
    localparam int EXPECT_POOL    = 3;
    localparam int EXPECT_ADD     = 6;
    localparam int EXPECT_EXEC    = EXPECT_CONV + EXPECT_POOL + EXPECT_ADD;
    localparam int EXPECT_DMA_LD  = 46;
    localparam int EXPECT_WGT_LD  = 27;
    localparam int EXPECT_COPY    = 0;
    localparam int EXPECT_STORE   = 17;
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
    logic [3:0]  debug_opcode;
    logic [63:0] debug_opcode_name;
    logic debug_instr_req, debug_instr_valid, debug_exec_valid, debug_dma_valid;
    logic [15:0] debug_exec_count, debug_conv_count, debug_pool_count, debug_add_count;
    logic debug_input_loaded;
    logic [15:0] debug_weight_load_count, debug_sram_copy_count, debug_store_count;
    int monitor_dma_seen = 0;
    int monitor_dma_ld_seen = 0;
    int monitor_dma_st_seen = 0;
    int monitor_exec_seen = 0;
    int debug_alias_check_count = 0;
    bit stage_store_armed = 1'b0;
    bit stage_store_checked = 1'b0;
    bit stage_load_armed = 1'b0;
    bit stage_load_checked = 1'b0;
    logic [31:0] stage_dram_addr;
    logic [31:0] stage_sram_src;
    logic [31:0] stage_sram_dst;
    logic [`DATA_BITS-1:0] stage_word;

    logic [`DATA_BITS-1:0] dram_in_mem  [0:INPUT_WORDS-1];
    logic [`DATA_BITS-1:0] dram_out_mem [0:OUTPUT_WORDS-1];
    logic [`DATA_BITS-1:0] dram_wgt_mem [0:WEIGHT_WORDS-1];
    byte unsigned weight_bytes [0:WEIGHT_BYTES-1];

    NPU_ctrl_top dut (
        .clk(clk), .rst(rst), .start(start), .halted(halted),
        .dram_en(dram_en), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata), .dram_rdata(dram_rdata),
        .debug_pc(debug_pc),
        .debug_opcode(debug_opcode),
        .debug_opcode_name(debug_opcode_name),
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

    initial begin
        if ($test$plusargs("FSDB")) begin
            $fsdbDumpfile("npu_ctrl_top.fsdb");
            $fsdbDumpvars(0, NPU_ctrl_top_tb, "+all");
            $fsdbDumpMDA(0, NPU_ctrl_top_tb);
        end
    end

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
        end else if (dut.i_dma.dma_dram < DRAM_OUTPUT_BASE) begin
            dma_kind = "DMA_LD DRAM_INPUT->SRAM";
        end else begin
            dma_kind = "DMA_LD DRAM_STAGE->SRAM";
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

    function automatic string opcode_name(input logic [3:0] op);
        case (op)
            `OP_CONV:   opcode_name = "CONV";
            `OP_POOL:   opcode_name = "POOL";
            `OP_CONCAT: opcode_name = "CONCAT";
            `OP_ADD:    opcode_name = "ADD";
            `OP_OTHER:  opcode_name = "OTHER";
            `OP_CONFIG: opcode_name = "CONFIG";
            `OP_BIAS:   opcode_name = "BIAS";
            `OP_DMA_LD: opcode_name = "DMA_LD";
            `OP_DMA_ST: opcode_name = "DMA_ST";
            `OP_ADDCFG: opcode_name = "ADDCFG";
            `OP_HALT:   opcode_name = "HALT";
            default:    opcode_name = "UNKNOWN";
        endcase
    endfunction

    function automatic logic [63:0] opcode_ascii(input logic [3:0] op);
        case (op)
            `OP_CONV:   opcode_ascii = "CONV    ";
            `OP_POOL:   opcode_ascii = "POOL    ";
            `OP_CONCAT: opcode_ascii = "CONCAT  ";
            `OP_ADD:    opcode_ascii = "ADD     ";
            `OP_OTHER:  opcode_ascii = "OTHER   ";
            `OP_CONFIG: opcode_ascii = "CONFIG  ";
            `OP_BIAS:   opcode_ascii = "BIAS    ";
            `OP_DMA_LD: opcode_ascii = "DMA_LD  ";
            `OP_DMA_ST: opcode_ascii = "DMA_ST  ";
            `OP_ADDCFG: opcode_ascii = "ADDCFG  ";
            `OP_HALT:   opcode_ascii = "HALT    ";
            default:    opcode_ascii = "UNKNOWN ";
        endcase
    endfunction

    always @(posedge clk) begin
        if (!rst && dut.i_decoder.state == 3'd2) begin
            debug_alias_check_count++;
            if (debug_opcode !== dut.i_decoder.opcode) begin
                $fatal(1, "debug_opcode mismatch pc=%0d debug=0x%0h decoder=0x%0h",
                       debug_pc, debug_opcode, dut.i_decoder.opcode);
            end
            if (debug_opcode_name !== opcode_ascii(dut.i_decoder.opcode)) begin
                $fatal(1, "debug_opcode_name mismatch pc=%0d debug=%s expected=%s",
                       debug_pc, debug_opcode_name,
                       opcode_ascii(dut.i_decoder.opcode));
            end
            case (dut.i_decoder.opcode)
                `OP_CONFIG: begin
                    $display("[DECODE pc=%0d] CONFIG in_h=%0d in_w=%0d in_c=%0d out_c=%0d stride=%0d pcfg=0x%03h shift=0x%02h",
                             debug_pc,
                             `CFG_IN_H(dut.i_decoder.instr),
                             `CFG_IN_W(dut.i_decoder.instr),
                             `CFG_IN_C(dut.i_decoder.instr),
                             `CFG_OUT_C(dut.i_decoder.instr),
                             `CFG_STRIDE(dut.i_decoder.instr),
                             `CFG_PCONFIG(dut.i_decoder.instr),
                             `CFG_SHIFT(dut.i_decoder.instr));
                end
                `OP_ADDCFG: begin
                    $display("[DECODE pc=%0d] ADDCFG lhs_shift=0x%02h rhs_shift=0x%02h",
                             debug_pc,
                             `ADDCFG_LHS(dut.i_decoder.instr),
                             `ADDCFG_RHS(dut.i_decoder.instr));
                end
                `OP_DMA_LD, `OP_DMA_ST: begin
                    $display("[DECODE pc=%0d] %s dram=0x%08h sram=0x%08h size=0x%08h",
                             debug_pc,
                             opcode_name(dut.i_decoder.opcode),
                             `DMA_DRAM(dut.i_decoder.instr),
                             `DMA_SRAM(dut.i_decoder.instr),
                             `DMA_SIZE(dut.i_decoder.instr));
                end
                `OP_CONV, `OP_POOL, `OP_ADD: begin
                    $display("[DECODE pc=%0d] %s in=0x%08h wgt=0x%08h out=0x%08h flags=0x%03h stride=%0d pad=%0d kernel=%0d uses_cfg(H=%0d W=%0d IC=%0d OC=%0d pcfg=0x%03h shift=0x%02h add_lhs=0x%02h add_rhs=0x%02h)",
                             debug_pc,
                             opcode_name(dut.i_decoder.opcode),
                             `EXEC_IN(dut.i_decoder.instr),
                             `EXEC_WGT(dut.i_decoder.instr),
                             `EXEC_OUT(dut.i_decoder.instr),
                             `EXEC_FLAGS(dut.i_decoder.instr),
                             `EXEC_STRIDE(dut.i_decoder.instr),
                             `EXEC_PAD(dut.i_decoder.instr),
                             `EXEC_KERNEL(dut.i_decoder.instr),
                             dut.i_decoder.r_in_h,
                             dut.i_decoder.r_in_w,
                             dut.i_decoder.r_in_c,
                             dut.i_decoder.r_out_c,
                             dut.i_decoder.r_pconfig,
                             dut.i_decoder.r_shift,
                             dut.i_decoder.r_lhs,
                             dut.i_decoder.r_rhs);
                end
                `OP_HALT: begin
                    $display("[DECODE pc=%0d] HALT", debug_pc);
                end
                default: begin
                    $display("[DECODE pc=%0d] unsupported opcode=%s raw=0x%032h",
                             debug_pc,
                             opcode_name(dut.i_decoder.opcode),
                             dut.i_decoder.instr);
                end
            endcase
        end

        if (!rst && dut.i_dma.state == 2'd0 && dut.i_dma.dma_valid) begin
            monitor_dma_seen = monitor_dma_seen + 1;
            if (dut.i_dma.dma_is_store) begin
                monitor_dma_st_seen = monitor_dma_st_seen + 1;
            end else begin
                monitor_dma_ld_seen = monitor_dma_ld_seen + 1;
            end
            $display("[DMA %0d][pc=%0d] %s dram=0x%08h sram=0x%08h size=0x%08h",
                     monitor_dma_seen, debug_pc, dma_kind(),
                     dut.i_dma.dma_dram, dut.i_dma.dma_sram,
                     dut.i_dma.dma_size);

            if (!stage_store_armed
                && dut.i_dma.dma_is_store
                && dut.i_dma.dma_dram >= DRAM_OUTPUT_BASE) begin
                stage_store_armed = 1'b1;
                stage_dram_addr = dut.i_dma.dma_dram;
                stage_sram_src = dut.i_dma.dma_sram;
                stage_word = dut.i_sram.mem[dut.i_dma.dma_sram >> 2];
                $display("[CHECKPOINT] concat staging store armed sram=0x%08h dram=0x%08h word=0x%08h",
                         dut.i_dma.dma_sram, dut.i_dma.dma_dram, stage_word);
            end

            if (stage_store_checked
                && !stage_load_armed
                && !dut.i_dma.dma_is_store
                && dut.i_dma.dma_dram == stage_dram_addr) begin
                stage_load_armed = 1'b1;
                stage_sram_dst = dut.i_dma.dma_sram;
                $display("[CHECKPOINT] concat staging reload armed dram=0x%08h sram=0x%08h",
                         dut.i_dma.dma_dram, dut.i_dma.dma_sram);
            end
        end

        if (stage_store_armed && !stage_store_checked
            && dut.i_dma.state == 2'd3 && dut.i_dma.tr_is_store) begin
            stage_store_checked = 1'b1;
            if (dram_out_mem[(stage_dram_addr - DRAM_OUTPUT_BASE) >> 2] !== stage_word) begin
                $fatal(1, "Concat staging store mismatch: sram=0x%08h dram=0x%08h expect=0x%08h got=0x%08h",
                       stage_sram_src, stage_dram_addr, stage_word,
                       dram_out_mem[(stage_dram_addr - DRAM_OUTPUT_BASE) >> 2]);
            end
            $display("[CHECKPOINT] concat staging store matched dram=0x%08h word=0x%08h",
                     stage_dram_addr, stage_word);
        end

        if (stage_load_armed && !stage_load_checked
            && dut.i_dma.state == 2'd3 && !dut.i_dma.tr_is_store) begin
            stage_load_checked = 1'b1;
            if (dut.i_sram.mem[stage_sram_dst >> 2] !== stage_word) begin
                $fatal(1, "Concat staging reload mismatch: dram=0x%08h sram=0x%08h expect=0x%08h got=0x%08h",
                       stage_dram_addr, stage_sram_dst, stage_word,
                       dut.i_sram.mem[stage_sram_dst >> 2]);
            end
            $display("[CHECKPOINT] concat staging reload matched sram=0x%08h word=0x%08h",
                     stage_sram_dst, stage_word);
        end

        if (!rst && dut.i_compute.state == 4'd0
            && dut.i_compute.exec_valid) begin
            monitor_exec_seen = monitor_exec_seen + 1;
            $display("[EXEC %0d][pc=%0d] %s out=0x%08h H=%0d W=%0d OC=%0d stride=%0d pad=%0d kernel=%0d",
                     monitor_exec_seen, debug_pc,
                     exec_kind(dut.i_compute.exec_op),
                     dut.i_compute.exec_out_addr,
                     dut.i_compute.exec_in_h,
                     dut.i_compute.exec_in_w,
                     dut.i_compute.exec_out_c,
                     dut.i_compute.exec_stride,
                     dut.i_compute.exec_pad,
                     dut.i_compute.exec_kernel);
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
        $display("dma_ld=%0d dma_st=%0d input_loaded=%0b weight_ld=%0d sram_copy=%0d store=%0d",
                 monitor_dma_ld_seen, monitor_dma_st_seen,
                 debug_input_loaded, debug_weight_load_count,
                 debug_sram_copy_count, debug_store_count);

        check(halted === 1'b1, "HALT reached");
        check(debug_pc == 16'(EXPECT_PC), "PC is parked at HALT instruction");
        check(debug_alias_check_count == EXPECT_PC + 1,
              "debug opcode alias checked for every decoded instruction");
        check(debug_exec_count == 16'(EXPECT_EXEC), "all generated EXEC ops accepted");
        check(debug_conv_count == 16'(EXPECT_CONV), "CONV count matches generated ISA");
        check(debug_pool_count == 16'(EXPECT_POOL), "POOL count matches generated ISA");
        check(debug_add_count == 16'(EXPECT_ADD), "ADD count matches generated ISA");
        check(monitor_dma_ld_seen == EXPECT_DMA_LD, "DMA_LD count matches generated ISA");
        check(debug_input_loaded === 1'b1, "input DRAM load was observed");
        check(debug_weight_load_count == 16'(EXPECT_WGT_LD), "weight DMA_LD count matches generated ISA");
        check(debug_sram_copy_count == 16'(EXPECT_COPY), "no overloaded SRAM-copy DMA_LD was used");
        check(debug_store_count == 16'(EXPECT_STORE), "DMA_ST spill count matches generated ISA");
        check(monitor_dma_st_seen == EXPECT_STORE, "monitor saw every DMA_ST");
        check(stage_store_checked === 1'b1, "concat staging DMA_ST content was checked");
        check(stage_load_checked === 1'b1, "concat staging DMA_LD content was checked");

        check(!$isunknown(dram_out_mem[32'h001F_4000 >> 2])
              && dram_out_mem[32'h001F_4000 >> 2] != 32'h0,
              "P3-like final output received nonzero data");
        check(!$isunknown(dram_out_mem[32'h002B_C000 >> 2])
              && dram_out_mem[32'h002B_C000 >> 2] != 32'h0,
              "P4-like final output received nonzero data");
        check(!$isunknown(dram_out_mem[32'h0034_5800 >> 2])
              && dram_out_mem[32'h0034_5800 >> 2] != 32'h0,
              "P5-like final output received nonzero data");

        $display("== NPU_ctrl_top_tb PASS ==");
        $finish;
    end

endmodule
