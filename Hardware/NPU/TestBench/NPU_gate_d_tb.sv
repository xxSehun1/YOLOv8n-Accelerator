`timescale 1ns/1ps
`include "define.svh"

module NPU_gate_d_tb;
    localparam int CLK_HALF = 5;

    localparam logic [31:0] DRAM_INPUT_BASE  = 32'h0000_0000;
    localparam logic [31:0] DRAM_OUTPUT_BASE = 32'h0020_0000;
    localparam logic [31:0] DRAM_WEIGHT_BASE = 32'h0100_0000;

`ifdef GATED_SPPF
    localparam string TEST_NAME = "Gate D SPPF block";
    localparam string INPUT_FILE = "../../../Build/golden_sppf_input.bin";
    localparam string GOLDEN_FILE = "../../../Build/golden_sppf_output.bin";
    localparam int INPUT_BYTES = 32'h0000_C800;
    localparam int GOLDEN_BYTES = 32'h0001_9000;
    localparam logic [31:0] CHECK_SRAM_BASE = 32'h0000_0000;
    localparam int EXPECT_PC = 18;
    localparam int EXPECT_CONV = 1;
    localparam int EXPECT_POOL = 3;
    localparam int EXPECT_ADD = 0;
    localparam int EXPECT_DMA_LD = 6;
    localparam int EXPECT_DMA_ST = 4;
    localparam int EXPECT_WEIGHT_LD = 1;
`else
    localparam string TEST_NAME = "Gate D first residual ADD";
    localparam string INPUT_FILE = "../../../Build/input_seed0.bin";
    localparam string GOLDEN_FILE = "../../../Build/golden_first_add.bin";
    localparam int INPUT_BYTES = 32'h0012_C000;
    localparam int GOLDEN_BYTES = 32'h0006_4000;
    localparam logic [31:0] CHECK_SRAM_BASE = 32'h0000_0000;
    localparam int EXPECT_PC = 19;
    localparam int EXPECT_CONV = 5;
    localparam int EXPECT_POOL = 0;
    localparam int EXPECT_ADD = 1;
    localparam int EXPECT_DMA_LD = 6;
    localparam int EXPECT_DMA_ST = 0;
    localparam int EXPECT_WEIGHT_LD = 5;
`endif

    localparam int WEIGHT_BYTES = 2 * 1024 * 1024;
    localparam int OUTPUT_BYTES = 14 * 1024 * 1024;
    localparam int INPUT_WORDS  = INPUT_BYTES / 4;
    localparam int GOLDEN_WORDS = GOLDEN_BYTES / 4;
    localparam int WEIGHT_WORDS = WEIGHT_BYTES / 4;
    localparam int OUTPUT_WORDS = OUTPUT_BYTES / 4;
    localparam int EXPECT_EXEC = EXPECT_CONV + EXPECT_POOL + EXPECT_ADD;

    logic clk = 1'b0;
    logic rst;
    logic start;
    logic halted;

    logic dram_en;
    logic dram_we;
    logic [31:0] dram_addr;
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
    logic [`DATA_BITS-1:0] dram_out_mem [0:OUTPUT_WORDS-1];
    logic [`DATA_BITS-1:0] dram_wgt_mem [0:WEIGHT_WORDS-1];
    byte unsigned input_bytes  [0:INPUT_BYTES-1];
    byte unsigned weight_bytes [0:WEIGHT_BYTES-1];
    byte unsigned golden_bytes [0:GOLDEN_BYTES-1];

    int decode_seen = 0;
    int dma_ld_seen = 0;
    int dma_st_seen = 0;
    int exec_seen = 0;

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

    function automatic string opcode_name(input logic [3:0] op);
        case (op)
            `OP_CONV:   opcode_name = "CONV";
            `OP_POOL:   opcode_name = "POOL";
            `OP_ADD:    opcode_name = "ADD";
            `OP_CONFIG: opcode_name = "CONFIG";
            `OP_DMA_LD: opcode_name = "DMA_LD";
            `OP_DMA_ST: opcode_name = "DMA_ST";
            `OP_ADDCFG: opcode_name = "ADDCFG";
            `OP_HALT:   opcode_name = "HALT";
            default:    opcode_name = "OTHER";
        endcase
    endfunction

    function automatic string exec_name(input logic [1:0] op);
        case (op)
            2'd0: exec_name = "CONV";
            2'd1: exec_name = "POOL";
            2'd2: exec_name = "ADD";
            default: exec_name = "UNKNOWN";
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

    always @(posedge clk) begin
        if (dram_en) begin
            if (in_weight_region(dram_addr)) begin
                if (dram_we) begin
                    $fatal(1, "Unexpected write to weight DRAM addr=0x%08h", dram_addr);
                end
                dram_rdata <= dram_wgt_mem[(dram_addr - DRAM_WEIGHT_BASE) >> 2];
            end else if (in_output_region(dram_addr)) begin
                if (dram_we) begin
                    dram_out_mem[(dram_addr - DRAM_OUTPUT_BASE) >> 2] <= dram_wdata;
                end
                dram_rdata <= dram_out_mem[(dram_addr - DRAM_OUTPUT_BASE) >> 2];
            end else if (in_input_region(dram_addr)) begin
                if (dram_we) begin
                    $fatal(1, "Unexpected write to input DRAM addr=0x%08h", dram_addr);
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

    always @(posedge clk) begin
        if (!rst && dut.i_decoder.state == 3'd2) begin
            decode_seen++;
            if (debug_opcode_name !== opcode_ascii(dut.i_decoder.opcode)) begin
                $fatal(1, "debug_opcode_name mismatch pc=%0d debug=%s expected=%s",
                       debug_pc, debug_opcode_name, opcode_ascii(dut.i_decoder.opcode));
            end
            case (dut.i_decoder.opcode)
                `OP_CONFIG:
                    $display("[DECODE pc=%0d] CONFIG H=%0d W=%0d IC=%0d OC=%0d stride=%0d shift=0x%02h",
                             debug_pc, `CFG_IN_H(dut.i_decoder.instr),
                             `CFG_IN_W(dut.i_decoder.instr),
                             `CFG_IN_C(dut.i_decoder.instr),
                             `CFG_OUT_C(dut.i_decoder.instr),
                             `CFG_STRIDE(dut.i_decoder.instr),
                             `CFG_SHIFT(dut.i_decoder.instr));
                `OP_ADDCFG:
                    $display("[DECODE pc=%0d] ADDCFG lhs=0x%02h rhs=0x%02h",
                             debug_pc, `ADDCFG_LHS(dut.i_decoder.instr),
                             `ADDCFG_RHS(dut.i_decoder.instr));
                `OP_DMA_LD, `OP_DMA_ST:
                    $display("[DECODE pc=%0d] %s dram=0x%08h sram=0x%08h size=0x%08h",
                             debug_pc, opcode_name(dut.i_decoder.opcode),
                             `DMA_DRAM(dut.i_decoder.instr),
                             `DMA_SRAM(dut.i_decoder.instr),
                             `DMA_SIZE(dut.i_decoder.instr));
                `OP_CONV, `OP_POOL, `OP_ADD:
                    $display("[DECODE pc=%0d] %s in=0x%08h wgt=0x%08h out=0x%08h stride=%0d pad=%0d kernel=%0d",
                             debug_pc, opcode_name(dut.i_decoder.opcode),
                             `EXEC_IN(dut.i_decoder.instr),
                             `EXEC_WGT(dut.i_decoder.instr),
                             `EXEC_OUT(dut.i_decoder.instr),
                             `EXEC_STRIDE(dut.i_decoder.instr),
                             `EXEC_PAD(dut.i_decoder.instr),
                             `EXEC_KERNEL(dut.i_decoder.instr));
                `OP_HALT:
                    $display("[DECODE pc=%0d] HALT", debug_pc);
                default:
                    $display("[DECODE pc=%0d] opcode=%s", debug_pc, opcode_name(dut.i_decoder.opcode));
            endcase
        end

        if (!rst && dut.i_dma.state == 2'd0 && dut.i_dma.dma_valid) begin
            if (dut.i_dma.dma_is_store) dma_st_seen++;
            else dma_ld_seen++;
            $display("[DMA pc=%0d] %s dram=0x%08h sram=0x%08h size=0x%08h",
                     debug_pc,
                     dut.i_dma.dma_is_store ? "DMA_ST" : "DMA_LD",
                     dut.i_dma.dma_dram, dut.i_dma.dma_sram, dut.i_dma.dma_size);
        end

        if (!rst && dut.i_compute.state == 4'd0 && dut.i_compute.exec_valid) begin
            exec_seen++;
            $display("[EXEC_ACCEPT %0d][pc=%0d] %s H=%0d W=%0d IC=%0d OC=%0d out=0x%08h",
                     exec_seen, debug_pc, exec_name(dut.i_compute.exec_op),
                     dut.i_compute.exec_in_h, dut.i_compute.exec_in_w,
                     dut.i_compute.exec_in_c, dut.i_compute.exec_out_c,
                     dut.i_compute.exec_out_addr);
        end

        if (!rst && dut.i_compute.state == 4'd5
            && ((dut.i_compute.output_byte_idx[17:0] == 18'h3ffff)
                || (dut.i_compute.output_byte_idx == dut.i_compute.total_out_bytes - 1))) begin
            $display("[COMPUTE_WRITE pc=%0d] %s byte_offset=0x%08h total=0x%08h",
                     debug_pc, exec_name(dut.i_compute.exec_op_l),
                     dut.i_compute.output_byte_idx, dut.i_compute.total_out_bytes);
        end
    end

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $fatal(1, "CHECK FAILED: %s", message);
        end
        $display("  PASS: %s", message);
    endtask

    task automatic load_input;
        int fd;
        int nread;
        begin
            fd = $fopen(INPUT_FILE, "rb");
            if (fd == 0) $fatal(1, "Cannot open %s", INPUT_FILE);
            nread = $fread(input_bytes, fd);
            $fclose(fd);
            if (nread != INPUT_BYTES) begin
                $fatal(1, "%s size mismatch: got %0d expected %0d",
                       INPUT_FILE, nread, INPUT_BYTES);
            end
            for (int i = 0; i < INPUT_BYTES; i += 4) begin
                dram_in_mem[i >> 2] = {
                    input_bytes[i + 3],
                    input_bytes[i + 2],
                    input_bytes[i + 1],
                    input_bytes[i]
                };
            end
            $display("[TB] loaded %0d input bytes from %s", nread, INPUT_FILE);
        end
    endtask

    task automatic load_weights;
        int fd;
        int nread;
        begin
            fd = $fopen("../../../Build/weights.bin", "rb");
            if (fd == 0) $fatal(1, "Cannot open ../../../Build/weights.bin");
            nread = $fread(weight_bytes, fd);
            $fclose(fd);
            for (int i = 0; i < nread; i += 4) begin
                dram_wgt_mem[i >> 2] = {
                    (i + 3 < nread) ? weight_bytes[i + 3] : 8'h00,
                    (i + 2 < nread) ? weight_bytes[i + 2] : 8'h00,
                    (i + 1 < nread) ? weight_bytes[i + 1] : 8'h00,
                    weight_bytes[i]
                };
            end
            $display("[TB] loaded %0d weight bytes", nread);
        end
    endtask

    task automatic load_golden;
        int fd;
        int nread;
        begin
            fd = $fopen(GOLDEN_FILE, "rb");
            if (fd == 0) $fatal(1, "Cannot open %s", GOLDEN_FILE);
            nread = $fread(golden_bytes, fd);
            $fclose(fd);
            if (nread != GOLDEN_BYTES) begin
                $fatal(1, "%s size mismatch: got %0d expected %0d",
                       GOLDEN_FILE, nread, GOLDEN_BYTES);
            end
            $display("[TB] loaded %0d golden bytes from %s", nread, GOLDEN_FILE);
        end
    endtask

    initial begin
        for (int i = 0; i < OUTPUT_WORDS; i++) dram_out_mem[i] = '0;
        for (int i = 0; i < WEIGHT_WORDS; i++) dram_wgt_mem[i] = '0;
        load_input();
        load_weights();
        load_golden();
    end

    initial begin
        int mismatch_count;
        logic [31:0] got_word;
        logic [31:0] exp_word;

        $display("== NPU_gate_d_tb: %s ==", TEST_NAME);
        $display("Requires npu_program.hex in this simulation cwd.");

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
                wait (halted === 1'b1);
                $display("[TB] HALT observed at %0t", $time);
            end
            begin
                repeat (1_000_000_000) @(posedge clk);
                $fatal(1, "Timeout waiting for HALT pc=%0d exec=%0d conv=%0d pool=%0d add=%0d",
                       debug_pc, debug_exec_count, debug_conv_count,
                       debug_pool_count, debug_add_count);
            end
        join_any
        disable fork;

        $display("== Gate D checkpoints ==");
        check(halted === 1'b1, "HALT reached");
        check(debug_pc == 16'(EXPECT_PC), "PC parked at expected HALT");
        check(decode_seen == EXPECT_PC + 1, "decoded every instruction including HALT");
        check(debug_exec_count == 16'(EXPECT_EXEC), "EXEC count matches target program");
        check(debug_conv_count == 16'(EXPECT_CONV), "CONV count matches target program");
        check(debug_pool_count == 16'(EXPECT_POOL), "POOL count matches target program");
        check(debug_add_count == 16'(EXPECT_ADD), "ADD count matches target program");
        check(dma_ld_seen == EXPECT_DMA_LD, "DMA_LD count matches target program");
        check(dma_st_seen == EXPECT_DMA_ST, "DMA_ST count matches target program");
        check(debug_weight_load_count == 16'(EXPECT_WEIGHT_LD), "weight DMA_LD count matches target program");
        check(debug_sram_copy_count == 16'd0, "no overloaded SRAM-copy DMA_LD was used");
        check(debug_input_loaded === 1'b1, "input DMA_LD was observed");

        mismatch_count = 0;
        for (int i = 0; i < GOLDEN_WORDS; i++) begin
            got_word = dut.i_sram.mem[(CHECK_SRAM_BASE >> 2) + i];
            exp_word = golden_word(i);
            if (got_word !== exp_word) begin
                if (mismatch_count < 16) begin
                    $display("  MISMATCH word=%0d byte_addr=0x%08h got=0x%08h expected=0x%08h",
                             i, CHECK_SRAM_BASE + (i << 2), got_word, exp_word);
                end
                mismatch_count++;
            end
        end
        check(mismatch_count == 0,
              $sformatf("%s output byte-for-byte matches %s", TEST_NAME, GOLDEN_FILE));

        $display("== NPU_gate_d_tb PASS: %s ==", TEST_NAME);
        $finish;
    end
endmodule
