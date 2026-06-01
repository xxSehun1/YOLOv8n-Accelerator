`timescale 1ns/1ps
`include "define.svh"

module NPU_first_conv_tb;
    localparam int CLK_HALF = 5;

    localparam logic [31:0] DRAM_INPUT_BASE  = 32'h0000_0000;
    localparam logic [31:0] DRAM_OUTPUT_BASE = 32'h0020_0000;
    localparam logic [31:0] DRAM_WEIGHT_BASE = 32'h0100_0000;

`ifdef GATEC_FULL
    localparam int GATEC_IN_H  = 640;
    localparam int GATEC_IN_W  = 640;
    localparam int GATEC_OUT_H = 320;
    localparam int GATEC_OUT_W = 320;
    localparam string GATEC_NAME = "full 640x640";
    localparam string INPUT_FILE = "../../../Build/input_seed0.bin";
    localparam string GOLDEN_FILE = "../../../Build/golden_l0_conv.bin";
`else
    localparam int GATEC_IN_H  = 16;
    localparam int GATEC_IN_W  = 16;
    localparam int GATEC_OUT_H = 8;
    localparam int GATEC_OUT_W = 8;
    localparam string GATEC_NAME = "tiny 16x16";
    localparam string INPUT_FILE = "../../../Build/input_tiny16_seed0.bin";
    localparam string GOLDEN_FILE = "../../../Build/golden_l0_tiny16_conv.bin";
`endif

    localparam int INPUT_BYTES  = GATEC_IN_H * GATEC_IN_W * 3;
    localparam int WEIGHT_BYTES = 2 * 1024 * 1024;
    localparam int INPUT_WORDS  = INPUT_BYTES / 4;
    localparam int WEIGHT_WORDS = WEIGHT_BYTES / 4;

    localparam logic [31:0] FIRST_WEIGHT_DRAM = 32'h0100_0000;
    localparam logic [31:0] FIRST_WEIGHT_SRAM = 32'h0038_0000;
    localparam int          FIRST_WEIGHT_BYTES = 32'h0000_01F0;
    localparam int          FIRST_WEIGHT_WORDS = FIRST_WEIGHT_BYTES / 4;
    localparam logic [31:0] FIRST_OUT_SRAM = 32'h0012_C000;
    localparam int          FIRST_OUT_BYTES = GATEC_OUT_H * GATEC_OUT_W * 16;
    localparam int          FIRST_OUT_WORDS = FIRST_OUT_BYTES / 4;

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

    logic [`DATA_BITS-1:0] dram_in_mem  [0:INPUT_WORDS-1];
    logic [`DATA_BITS-1:0] dram_wgt_mem [0:WEIGHT_WORDS-1];
    byte unsigned input_bytes  [0:INPUT_BYTES-1];
    byte unsigned weight_bytes [0:WEIGHT_BYTES-1];
    byte unsigned golden_bytes [0:FIRST_OUT_BYTES-1];

    bit first_exec_seen = 1'b0;
    bit first_conv_done = 1'b0;
    int debug_alias_check_count = 0;

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

`ifndef NO_FSDB
    initial begin
        if ($test$plusargs("FSDB")) begin
            $fsdbDumpfile("npu_first_conv.fsdb");
            $fsdbDumpvars(0, NPU_first_conv_tb, "+all");
            $fsdbDumpMDA(0, NPU_first_conv_tb);
        end
    end
`endif

    always #CLK_HALF clk = ~clk;

    function automatic bit in_input_region(input logic [31:0] addr);
        in_input_region = (addr >= DRAM_INPUT_BASE)
                       && (addr <  DRAM_INPUT_BASE + INPUT_BYTES);
    endfunction

    function automatic bit in_weight_region(input logic [31:0] addr);
        in_weight_region = (addr >= DRAM_WEIGHT_BASE)
                        && (addr <  DRAM_WEIGHT_BASE + WEIGHT_BYTES);
    endfunction

    always @(posedge clk) begin
        if (dram_en) begin
            if (in_weight_region(dram_addr)) begin
                if (dram_we) begin
                    $fatal(1, "Unexpected write to weight DRAM addr=0x%08h", dram_addr);
                end
                dram_rdata <= dram_wgt_mem[(dram_addr - DRAM_WEIGHT_BASE) >> 2];
            end else if (in_input_region(dram_addr)) begin
                if (dram_we) begin
                    $fatal(1, "Unexpected write to input DRAM addr=0x%08h", dram_addr);
                end
                dram_rdata <= dram_in_mem[(dram_addr - DRAM_INPUT_BASE) >> 2];
            end else if (dram_addr >= DRAM_OUTPUT_BASE) begin
                dram_rdata <= '0;
                if (dram_we) begin
                    $fatal(1, "First-conv TB should not reach DMA_ST addr=0x%08h", dram_addr);
                end
            end else begin
                dram_rdata <= '0;
                if (dram_we) begin
                    $fatal(1, "Unexpected DRAM write addr=0x%08h data=0x%08h",
                           dram_addr, dram_wdata);
                end
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
            $display("[TB] loaded %0d weight bytes", nread);
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

    task automatic load_input;
        int fd;
        int nread;
        begin
            fd = $fopen(INPUT_FILE, "rb");
            if (fd == 0) begin
                $fatal(1, "Cannot open %s", INPUT_FILE);
            end
            nread = $fread(input_bytes, fd);
            $fclose(fd);
            if (nread != INPUT_BYTES) begin
                $fatal(1, "%s size mismatch: got %0d expected %0d",
                       INPUT_FILE, nread, INPUT_BYTES);
            end
            $display("[TB] loaded %0d input bytes", nread);
            for (int i = 0; i < INPUT_BYTES; i += 4) begin
                dram_in_mem[i >> 2] = {
                    input_bytes[i + 3],
                    input_bytes[i + 2],
                    input_bytes[i + 1],
                    input_bytes[i]
                };
            end
        end
    endtask

    task automatic load_golden_l0;
        int fd;
        int nread;
        begin
            fd = $fopen(GOLDEN_FILE, "rb");
            if (fd == 0) begin
                $fatal(1, "Cannot open %s", GOLDEN_FILE);
            end
            nread = $fread(golden_bytes, fd);
            $fclose(fd);
            if (nread != FIRST_OUT_BYTES) begin
                $fatal(1, "%s size mismatch: got %0d expected %0d",
                       GOLDEN_FILE, nread, FIRST_OUT_BYTES);
            end
            $display("[TB] loaded %0d golden L0 bytes", nread);
        end
    endtask

    function automatic logic [31:0] golden_word(input int word_idx);
        int byte_idx;
        begin
            byte_idx = word_idx << 2;
            golden_word = {
                golden_bytes[byte_idx + 3],
                golden_bytes[byte_idx + 2],
                golden_bytes[byte_idx + 1],
                golden_bytes[byte_idx]
            };
        end
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
                `OP_DMA_LD:
                    $display("[DECODE pc=%0d] DMA_LD dram=0x%08h sram=0x%08h size=0x%08h",
                             debug_pc, `DMA_DRAM(dut.i_decoder.instr),
                             `DMA_SRAM(dut.i_decoder.instr),
                             `DMA_SIZE(dut.i_decoder.instr));
                `OP_CONFIG:
                    $display("[DECODE pc=%0d] CONFIG H=%0d W=%0d IC=%0d OC=%0d stride=%0d pcfg=0x%03h shift=0x%02h",
                             debug_pc, `CFG_IN_H(dut.i_decoder.instr),
                             `CFG_IN_W(dut.i_decoder.instr),
                             `CFG_IN_C(dut.i_decoder.instr),
                             `CFG_OUT_C(dut.i_decoder.instr),
                             `CFG_STRIDE(dut.i_decoder.instr),
                             `CFG_PCONFIG(dut.i_decoder.instr),
                             `CFG_SHIFT(dut.i_decoder.instr));
                `OP_CONV:
                    $display("[DECODE pc=%0d] CONV in=0x%08h wgt=0x%08h out=0x%08h flags=0x%03h stride=%0d pad=%0d kernel=%0d uses_cfg(H=%0d W=%0d IC=%0d OC=%0d pcfg=0x%03h shift=0x%02h)",
                             debug_pc, `EXEC_IN(dut.i_decoder.instr),
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
                             dut.i_decoder.r_shift);
                `OP_HALT:
                    $display("[DECODE pc=%0d] HALT", debug_pc);
                default:
                    $display("[DECODE pc=%0d] opcode=0x%0h", debug_pc, dut.i_decoder.opcode);
            endcase
        end

        if (!rst && dut.i_dma.state == 2'd0 && dut.i_dma.dma_valid) begin
            $display("[DMA][pc=%0d] %s dram=0x%08h sram=0x%08h size=0x%08h",
                     debug_pc,
                     dut.i_dma.dma_is_store ? "DMA_ST SRAM->DRAM" :
                     ((dut.i_dma.dma_dram >= DRAM_WEIGHT_BASE) ?
                      "DMA_LD DRAM_WEIGHT->SRAM" : "DMA_LD DRAM_INPUT->SRAM"),
                     dut.i_dma.dma_dram, dut.i_dma.dma_sram, dut.i_dma.dma_size);
        end

        if (!rst && !first_exec_seen && dut.i_compute.state == 4'd0
            && dut.i_compute.exec_valid) begin
            first_exec_seen = 1'b1;
            $display("[EXEC_ACCEPT][pc=%0d] first CONV out=0x%08h H=%0d W=%0d OC=%0d stride=%0d pad=%0d kernel=%0d",
                     debug_pc, dut.i_compute.exec_out_addr,
                     dut.i_compute.exec_in_h,
                     dut.i_compute.exec_in_w,
                     dut.i_compute.exec_out_c,
                     dut.i_compute.exec_stride,
                     dut.i_compute.exec_pad,
                     dut.i_compute.exec_kernel);
        end

        if (!rst && dut.i_compute.state == 4'd1) begin
            $display("[COMPUTE][pc=%0d] start nested CONV addrgen in=0x%08h wgt=0x%08h out=0x%08h",
                     debug_pc,
                     dut.i_compute.in_addr_l,
                     dut.i_compute.wgt_addr_l,
                     dut.i_compute.out_addr_l);
        end

        if (!rst && dut.i_compute.state == 4'd5
            && ((FIRST_OUT_BYTES <= 4096 && dut.i_compute.output_byte_idx[7:0] == 8'hff)
                || (FIRST_OUT_BYTES > 4096 && dut.i_compute.output_byte_idx[15:0] == 16'hffff)
                || dut.i_compute.output_byte_idx == FIRST_OUT_BYTES - 1)) begin
            $display("[COMPUTE][pc=%0d] wrote through output byte offset 0x%08h oc=%0d oh=%0d ow=%0d",
                     debug_pc, dut.i_compute.output_byte_idx,
                     dut.i_compute.addr_oc, dut.i_compute.addr_oh, dut.i_compute.addr_ow);
        end

        if (!rst && !first_conv_done && dut.exec_done && debug_exec_count == 16'd1) begin
            first_conv_done = 1'b1;
            $display("[EXEC_DONE][pc=%0d] first CONV real output complete", debug_pc);
        end
    end

    initial begin
        for (int i = 0; i < WEIGHT_WORDS; i++) begin
            dram_wgt_mem[i] = 32'h0000_0000;
        end
        load_input();
        load_weights();
        load_golden_l0();
    end

    initial begin
        int mismatch_count;
        logic [31:0] got_word;
        logic [31:0] exp_word;

        $display("== NPU_first_conv_tb: Gate C %s first real CONV bit-exact check ==", GATEC_NAME);

        rst = 1'b1;
        start = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        $display("[TB] start pulsed at %0t", $time);

        fork
            begin
                wait (first_conv_done === 1'b1);
                $display("[TB] first CONV completed at %0t", $time);
                wait (halted === 1'b1);
                $display("[TB] HALT observed at %0t", $time);
            end
            begin
                repeat (100_000_000) @(posedge clk);
                $fatal(1, "Timeout waiting for first CONV/HALT. pc=%0d exec=%0d halted=%0b",
                       debug_pc, debug_exec_count, halted);
            end
        join_any
        disable fork;

        $display("== First CONV checkpoints ==");
        check(debug_exec_count == 16'd1, "exactly one EXEC op completed");
        check(debug_alias_check_count == 5, "debug opcode alias checked through first CONV and HALT");
        check(debug_conv_count == 16'd1, "first EXEC was CONV");
        check(debug_pool_count == 16'd0, "no POOL executed");
        check(debug_add_count == 16'd0, "no ADD executed");
        check(halted === 1'b1, "HALT reached after first CONV");
        check(debug_input_loaded === 1'b1, "input DMA_LD was observed");
        check(debug_weight_load_count == 16'd1, "one weight DMA_LD was observed");
        check(debug_store_count == 16'd0, "no DMA_ST before first CONV completes");

        check(dut.i_sram.mem[32'h0000_0000 >> 2] === dram_in_mem[0],
              "input first word copied DRAM->SRAM");
        check(dut.i_sram.mem[(INPUT_BYTES >> 2) - 1] === dram_in_mem[INPUT_WORDS - 1],
              "input last word copied DRAM->SRAM");
        check(dut.i_sram.mem[FIRST_WEIGHT_SRAM >> 2] === dram_wgt_mem[(FIRST_WEIGHT_DRAM - DRAM_WEIGHT_BASE) >> 2],
              "weight first word copied DRAM->SRAM");
        check(dut.i_sram.mem[(FIRST_WEIGHT_SRAM >> 2) + FIRST_WEIGHT_WORDS - 1]
              === dram_wgt_mem[((FIRST_WEIGHT_DRAM - DRAM_WEIGHT_BASE) >> 2) + FIRST_WEIGHT_WORDS - 1],
              "weight last word copied DRAM->SRAM");

        mismatch_count = 0;
        for (int i = 0; i < FIRST_OUT_WORDS; i++) begin
            got_word = dut.i_sram.mem[(FIRST_OUT_SRAM >> 2) + i];
            exp_word = golden_word(i);
            if (got_word !== exp_word) begin
                if (mismatch_count < 16) begin
                    $display("  MISMATCH word=%0d byte_addr=0x%08h got=0x%08h expected=0x%08h",
                             i, FIRST_OUT_SRAM + (i << 2), got_word, exp_word);
                end
                mismatch_count++;
            end
        end
        check(mismatch_count == 0,
              $sformatf("Gate C %s first CONV output byte-for-byte matches %s",
                        GATEC_NAME, GOLDEN_FILE));

        $display("== NPU_first_conv_tb GATE C PASS ==");
        $finish;
    end

endmodule
