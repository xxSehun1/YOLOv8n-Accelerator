`timescale 1ns/1ps
`include "define.svh"

module NPU_gate_e_tb;
    localparam int CLK_HALF = 5;

    localparam logic [31:0] DRAM_INPUT_BASE  = 32'h0000_0000;
    localparam logic [31:0] DRAM_OUTPUT_BASE = 32'h0020_0000;
    localparam logic [31:0] DRAM_WEIGHT_BASE = 32'h0100_0000;

    localparam int INPUT_BYTES  = 32'h0012_C000;
    localparam int OUTPUT_BYTES = 14 * 1024 * 1024;
    localparam int WEIGHT_BYTES = 2 * 1024 * 1024;

    localparam int INPUT_WORDS  = INPUT_BYTES / 4;
    localparam int OUTPUT_WORDS = OUTPUT_BYTES / 4;
    localparam int WEIGHT_WORDS = WEIGHT_BYTES / 4;

    localparam int EXPECT_PC      = 141;
    localparam int EXPECT_CONV    = 27;
    localparam int EXPECT_POOL    = 3;
    localparam int EXPECT_ADD     = 6;
    localparam int EXPECT_EXEC    = EXPECT_CONV + EXPECT_POOL + EXPECT_ADD;
    localparam int EXPECT_DMA_LD  = 46;
    localparam int EXPECT_DMA_ST  = 17;
    localparam int EXPECT_WGT_LD  = 27;
    localparam int EXPECT_COPY    = 0;

    localparam logic [31:0] P3_DRAM_ADDR = 32'h003F_4000;
    localparam logic [31:0] P4_DRAM_ADDR = 32'h004B_C000;
    localparam logic [31:0] P5_DRAM_ADDR = 32'h0054_5800;
    localparam int P3_BYTES = 32'h0006_4000;
    localparam int P4_BYTES = 32'h0003_2000;
    localparam int P5_BYTES = 32'h0001_9000;
    localparam int P3_WORDS = P3_BYTES / 4;
    localparam int P4_WORDS = P4_BYTES / 4;
    localparam int P5_WORDS = P5_BYTES / 4;

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
    byte unsigned input_bytes [0:INPUT_BYTES-1];
    byte unsigned weight_bytes [0:WEIGHT_BYTES-1];
    byte unsigned golden_p3 [0:P3_BYTES-1];
    byte unsigned golden_p4 [0:P4_BYTES-1];
    byte unsigned golden_p5 [0:P5_BYTES-1];

    int decode_seen = 0;
    int dma_ld_seen = 0;
    int dma_st_seen = 0;
    int exec_seen = 0;
    bit p3_store_seen = 1'b0;
    bit p4_store_seen = 1'b0;
    bit p5_store_seen = 1'b0;

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

    function automatic logic [31:0] golden_word_p3(input int word_idx);
        int b;
        begin
            b = word_idx << 2;
            golden_word_p3 = {golden_p3[b + 3], golden_p3[b + 2], golden_p3[b + 1], golden_p3[b]};
        end
    endfunction

    function automatic logic [31:0] golden_word_p4(input int word_idx);
        int b;
        begin
            b = word_idx << 2;
            golden_word_p4 = {golden_p4[b + 3], golden_p4[b + 2], golden_p4[b + 1], golden_p4[b]};
        end
    endfunction

    function automatic logic [31:0] golden_word_p5(input int word_idx);
        int b;
        begin
            b = word_idx << 2;
            golden_word_p5 = {golden_p5[b + 3], golden_p5[b + 2], golden_p5[b + 1], golden_p5[b]};
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
            if ((debug_pc % 16) == 0 || dut.i_decoder.opcode == `OP_HALT) begin
                $display("[DECODE pc=%0d] opcode=%s", debug_pc, debug_opcode_name);
            end
        end

        if (!rst && dut.i_dma.state == 2'd0 && dut.i_dma.dma_valid) begin
            if (dut.i_dma.dma_is_store) begin
                dma_st_seen++;
                if (dut.i_dma.dma_dram == P3_DRAM_ADDR) p3_store_seen = 1'b1;
                if (dut.i_dma.dma_dram == P4_DRAM_ADDR) p4_store_seen = 1'b1;
                if (dut.i_dma.dma_dram == P5_DRAM_ADDR) p5_store_seen = 1'b1;
                $display("[DMA_ST %0d][pc=%0d] dram=0x%08h sram=0x%08h size=0x%08h",
                         dma_st_seen, debug_pc,
                         dut.i_dma.dma_dram, dut.i_dma.dma_sram, dut.i_dma.dma_size);
            end else begin
                dma_ld_seen++;
            end
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
            && dut.i_compute.output_byte_idx == dut.i_compute.total_out_bytes - 1) begin
            $display("[COMPUTE_DONE pc=%0d] %s total=0x%08h out=0x%08h",
                     debug_pc, exec_name(dut.i_compute.exec_op_l),
                     dut.i_compute.total_out_bytes, dut.i_compute.out_addr_l);
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
            fd = $fopen("../../../Build/input_seed0.bin", "rb");
            if (fd == 0) $fatal(1, "Cannot open ../../../Build/input_seed0.bin");
            nread = $fread(input_bytes, fd);
            $fclose(fd);
            if (nread != INPUT_BYTES) begin
                $fatal(1, "input_seed0.bin size mismatch: got %0d expected %0d", nread, INPUT_BYTES);
            end
            for (int i = 0; i < INPUT_BYTES; i += 4) begin
                dram_in_mem[i >> 2] = {
                    input_bytes[i + 3],
                    input_bytes[i + 2],
                    input_bytes[i + 1],
                    input_bytes[i]
                };
            end
            $display("[TB] loaded %0d input bytes", nread);
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

    task automatic load_golden_p3;
        int fd;
        int nread;
        begin
            fd = $fopen("../../../Build/golden_p3.bin", "rb");
            if (fd == 0) $fatal(1, "Cannot open ../../../Build/golden_p3.bin");
            nread = $fread(golden_p3, fd);
            $fclose(fd);
            if (nread != P3_BYTES) begin
                $fatal(1, "golden_p3.bin size mismatch: got %0d expected %0d", nread, P3_BYTES);
            end
            $display("[TB] loaded %0d golden P3 bytes", nread);
        end
    endtask

    task automatic load_golden_p4;
        int fd;
        int nread;
        begin
            fd = $fopen("../../../Build/golden_p4.bin", "rb");
            if (fd == 0) $fatal(1, "Cannot open ../../../Build/golden_p4.bin");
            nread = $fread(golden_p4, fd);
            $fclose(fd);
            if (nread != P4_BYTES) begin
                $fatal(1, "golden_p4.bin size mismatch: got %0d expected %0d", nread, P4_BYTES);
            end
            $display("[TB] loaded %0d golden P4 bytes", nread);
        end
    endtask

    task automatic load_golden_p5;
        int fd;
        int nread;
        begin
            fd = $fopen("../../../Build/golden_p5.bin", "rb");
            if (fd == 0) $fatal(1, "Cannot open ../../../Build/golden_p5.bin");
            nread = $fread(golden_p5, fd);
            $fclose(fd);
            if (nread != P5_BYTES) begin
                $fatal(1, "golden_p5.bin size mismatch: got %0d expected %0d", nread, P5_BYTES);
            end
            $display("[TB] loaded %0d golden P5 bytes", nread);
        end
    endtask

    task automatic compare_region(
        input string name,
        input logic [31:0] dram_base,
        input int words,
        input int golden_sel,
        inout int mismatch_count
    );
        logic [31:0] got_word;
        logic [31:0] exp_word;
        begin
            for (int i = 0; i < words; i++) begin
                got_word = dram_out_mem[((dram_base - DRAM_OUTPUT_BASE) >> 2) + i];
                case (golden_sel)
                    0: exp_word = golden_word_p3(i);
                    1: exp_word = golden_word_p4(i);
                    default: exp_word = golden_word_p5(i);
                endcase
                if (got_word !== exp_word) begin
                    if (mismatch_count < 24) begin
                        $display("  MISMATCH %s word=%0d dram=0x%08h got=0x%08h expected=0x%08h",
                                 name, i, dram_base + (i << 2), got_word, exp_word);
                    end
                    mismatch_count++;
                end
            end
        end
    endtask

    initial begin
        for (int i = 0; i < OUTPUT_WORDS; i++) dram_out_mem[i] = '0;
        for (int i = 0; i < WEIGHT_WORDS; i++) dram_wgt_mem[i] = '0;
        load_input();
        load_weights();
        load_golden_p3();
        load_golden_p4();
        load_golden_p5();
    end

    initial begin
        int mismatch_count;

        $display("== NPU_gate_e_tb: full YOLOv8n backbone Gate E ==");
        $display("Requires full Build/npu_program.hex copied to simulation cwd.");

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
                longint unsigned timeout_cycles;
                timeout_cycles = 64'd3_000_000_000;
                while (timeout_cycles != 0 && halted !== 1'b1) begin
                    @(posedge clk);
                    timeout_cycles--;
                end
                if (halted !== 1'b1) begin
                    $fatal(1, "Timeout waiting for HALT pc=%0d exec=%0d conv=%0d pool=%0d add=%0d dma_st=%0d",
                           debug_pc, debug_exec_count, debug_conv_count,
                           debug_pool_count, debug_add_count, dma_st_seen);
                end
            end
        join_any
        disable fork;

        $display("== Gate E checkpoints ==");
        check(halted === 1'b1, "HALT reached");
        check(debug_pc == 16'(EXPECT_PC), "PC parked at HALT instruction");
        check(decode_seen == EXPECT_PC + 1, "decoded every instruction including HALT");
        check(debug_exec_count == 16'(EXPECT_EXEC), "EXEC count matches generated ISA");
        check(debug_conv_count == 16'(EXPECT_CONV), "CONV count matches generated ISA");
        check(debug_pool_count == 16'(EXPECT_POOL), "POOL count matches generated ISA");
        check(debug_add_count == 16'(EXPECT_ADD), "ADD count matches generated ISA");
        check(dma_ld_seen == EXPECT_DMA_LD, "DMA_LD count matches generated ISA");
        check(dma_st_seen == EXPECT_DMA_ST, "DMA_ST count matches generated ISA");
        check(debug_weight_load_count == 16'(EXPECT_WGT_LD), "weight DMA_LD count matches generated ISA");
        check(debug_store_count == 16'(EXPECT_DMA_ST), "DMA_ST debug count matches generated ISA");
        check(debug_sram_copy_count == 16'(EXPECT_COPY), "no overloaded SRAM-copy DMA_LD was used");
        check(debug_input_loaded === 1'b1, "input DMA_LD was observed");
        check(p3_store_seen === 1'b1, "P3 final DMA_ST observed");
        check(p4_store_seen === 1'b1, "P4 final DMA_ST observed");
        check(p5_store_seen === 1'b1, "P5 final DMA_ST observed");

        mismatch_count = 0;
        compare_region("P3", P3_DRAM_ADDR, P3_WORDS, 0, mismatch_count);
        compare_region("P4", P4_DRAM_ADDR, P4_WORDS, 1, mismatch_count);
        compare_region("P5", P5_DRAM_ADDR, P5_WORDS, 2, mismatch_count);
        check(mismatch_count == 0, "P3/P4/P5 combined mismatch_count is exactly 0");

        $display("== NPU_gate_e_tb GATE E PASS ==");
        $finish;
    end
endmodule
