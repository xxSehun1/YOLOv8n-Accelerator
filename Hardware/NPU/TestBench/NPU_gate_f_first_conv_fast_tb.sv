`timescale 1ns/1ps
`include "define.svh"

module NPU_gate_f_first_conv_fast_tb;
    localparam int CLK_HALF = 5;

    localparam int IN_H = 640;
    localparam int IN_W = 640;
    localparam int IN_C = 3;
    localparam int OUT_H = 320;
    localparam int OUT_W = 320;
    localparam int OUT_C = 16;

    localparam int INPUT_BYTES  = IN_H * IN_W * IN_C;
    localparam int OUTPUT_BYTES = OUT_H * OUT_W * OUT_C;
    localparam int WEIGHT_BYTES = 32'h0000_01f0;
    localparam int OUTPUT_WORDS = OUTPUT_BYTES / 4;

    localparam logic [31:0] IN_SRAM        = 32'h0000_0000;
    localparam logic [31:0] WGT_SRAM       = 32'h0038_0000;
    localparam logic [31:0] FIRST_OUT_SRAM = 32'h0012_c000;

    localparam logic [127:0] INS_CONFIG = 128'h60280028000030010200000000001f8a;
    localparam logic [127:0] INS_CONV   = 128'h100000000003800000012c00000b2130;
    localparam logic [127:0] INS_HALT   = 128'hf0000000000000000000000000000000;

    logic clk = 1'b0;
    logic rst;
    logic start;
    logic halted;

    logic dram_en;
    logic dram_we;
    logic [31:0] dram_addr;
    logic [`DATA_BITS-1:0] dram_wdata;
    logic [`DATA_BITS-1:0] dram_rdata;

    byte unsigned input_bytes  [0:INPUT_BYTES-1];
    byte unsigned weight_bytes [0:WEIGHT_BYTES-1];
    byte unsigned golden_bytes [0:OUTPUT_BYTES-1];

    int cycle;
    int mon_act_count;

    NPU_top dut (
        .clk(clk), .rst(rst), .start(start), .halted(halted),
        .dram_en(dram_en), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata), .dram_rdata(dram_rdata)
    );

    always #CLK_HALF clk = ~clk;

    assign dram_rdata = '0;

    function automatic logic [31:0] golden_word(input int word_idx);
        int b;
        begin
            b = word_idx << 2;
            golden_word = {golden_bytes[b + 3],
                           golden_bytes[b + 2],
                           golden_bytes[b + 1],
                           golden_bytes[b]};
        end
    endfunction

    function automatic logic [31:0] golden_act_word(input int act_idx);
        int pixel;
        int group;
        int c0;
        begin
            pixel = act_idx >> 2;
            group = act_idx & 3;
            c0 = group << 2;
            golden_act_word = {golden_bytes[(c0 + 3) * OUT_H * OUT_W + pixel],
                               golden_bytes[(c0 + 2) * OUT_H * OUT_W + pixel],
                               golden_bytes[(c0 + 1) * OUT_H * OUT_W + pixel],
                               golden_bytes[(c0 + 0) * OUT_H * OUT_W + pixel]};
        end
    endfunction

    task automatic load_input_file(input string path);
        int fd;
        int nread;
        begin
            fd = $fopen(path, "rb");
            if (fd == 0) $fatal(1, "Cannot open %s", path);
            nread = $fread(input_bytes, fd);
            $fclose(fd);
            if (nread < INPUT_BYTES) $fatal(1, "%s size got %0d expected at least %0d", path, nread, INPUT_BYTES);
            $display("[TB] loaded %s bytes=%0d", path, nread);
        end
    endtask

    task automatic load_weight_file(input string path);
        int fd;
        int nread;
        begin
            fd = $fopen(path, "rb");
            if (fd == 0) $fatal(1, "Cannot open %s", path);
            nread = $fread(weight_bytes, fd);
            $fclose(fd);
            if (nread < WEIGHT_BYTES) $fatal(1, "%s size got %0d expected at least %0d", path, nread, WEIGHT_BYTES);
            $display("[TB] loaded %s bytes=%0d", path, nread);
        end
    endtask

    task automatic load_golden_file(input string path);
        int fd;
        int nread;
        begin
            fd = $fopen(path, "rb");
            if (fd == 0) $fatal(1, "Cannot open %s", path);
            nread = $fread(golden_bytes, fd);
            $fclose(fd);
            if (nread < OUTPUT_BYTES) $fatal(1, "%s size got %0d expected at least %0d", path, nread, OUTPUT_BYTES);
            $display("[TB] loaded %s bytes=%0d", path, nread);
        end
    endtask

    task automatic write_input_sram(input logic [31:0] base);
        logic [31:0] word;
        begin
            for (int i = 0; i < INPUT_BYTES; i += 4) begin
                word = {(i + 3 < INPUT_BYTES) ? input_bytes[i + 3] : 8'h00,
                        (i + 2 < INPUT_BYTES) ? input_bytes[i + 2] : 8'h00,
                        (i + 1 < INPUT_BYTES) ? input_bytes[i + 1] : 8'h00,
                        input_bytes[i]};
                dut.i_sram.mem[(base >> 2) + (i >> 2)] = word;
            end
        end
    endtask

    task automatic write_weight_sram(input logic [31:0] base);
        logic [31:0] word;
        begin
            for (int i = 0; i < WEIGHT_BYTES; i += 4) begin
                word = {(i + 3 < WEIGHT_BYTES) ? weight_bytes[i + 3] : 8'h00,
                        (i + 2 < WEIGHT_BYTES) ? weight_bytes[i + 2] : 8'h00,
                        (i + 1 < WEIGHT_BYTES) ? weight_bytes[i + 1] : 8'h00,
                        weight_bytes[i]};
                dut.i_sram.mem[(base >> 2) + (i >> 2)] = word;
            end
        end
    endtask

    initial begin
        load_input_file("../../../Build/input_seed0.bin");
        load_weight_file("../../../Build/weights.bin");
        load_golden_file("../../../Build/golden_l0_conv.bin");
    end

    always @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
            mon_act_count <= 0;
        end else begin
            cycle <= cycle + 1;
            if ((cycle % 100000) == 0) begin
                $display("[HB][%0t] cyc=%0d pc=%0d ppc_st=%0d tile_base=%0d tile_w=%0d oy=%0d opsum=%0d halted=%0b",
                         $time, cycle, dut.pc, dut.i_ppc.state,
                         dut.i_ppc.strip_ow_base, dut.i_ppc.strip_w,
                         dut.i_ppc.ifmap_oy, dut.i_ppc.opsum_count, halted);
            end

            if (dut.oc_act_valid && dut.oc_act_ready) begin
                if (dut.oc_act_data !== golden_act_word(mon_act_count)) begin
                    $fatal(1, "[ACT_MISMATCH] n=%0d got=0x%08h exp=0x%08h",
                           mon_act_count, dut.oc_act_data, golden_act_word(mon_act_count));
                end
                mon_act_count++;
            end
        end
    end

    initial begin
        int mismatch_count;
        logic [31:0] got_word;
        logic [31:0] exp_word;

        $display("== Gate F TRUE systolic fast full first-CONV check ==");

        rst = 1'b1;
        start = 1'b0;
        repeat (5) @(posedge clk);

        dut.i_cache.mem[0] = INS_CONFIG;
        dut.i_cache.mem[1] = INS_CONV;
        dut.i_cache.mem[2] = INS_HALT;
        for (int i = 3; i < 16; i++) dut.i_cache.mem[i] = INS_HALT;

        write_input_sram(IN_SRAM);
        write_weight_sram(WGT_SRAM);
        $display("[TB] backdoor SRAM preload done input=0x%08h weight=0x%08h", IN_SRAM, WGT_SRAM);

        rst = 1'b0;
        repeat (5) @(posedge clk);

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        $display("[TB] start pulsed at %0t", $time);

        fork
            begin
                wait (halted === 1'b1);
                $display("[TB] HALT observed at %0t cycle=%0d act_words=%0d",
                         $time, cycle, mon_act_count);
            end
            begin
                repeat (20_000_000) @(posedge clk);
                $fatal(1, "Timeout waiting HALT pc=%0d ppc_st=%0d cycle=%0d",
                       dut.pc, dut.i_ppc.state, cycle);
            end
        join_any
        disable fork;

        repeat (20) @(posedge clk);

        mismatch_count = 0;
        for (int i = 0; i < OUTPUT_WORDS; i++) begin
            got_word = dut.i_sram.mem[(FIRST_OUT_SRAM >> 2) + i];
            exp_word = golden_word(i);
            if (got_word !== exp_word) begin
                if (mismatch_count < 32) begin
                    $display("[MISMATCH] word=%0d byte_addr=0x%08h got=0x%08h exp=0x%08h",
                             i, FIRST_OUT_SRAM + (i << 2), got_word, exp_word);
                end
                mismatch_count++;
            end
        end

        $display("[RESULT] mismatch_count=%0d output_words=%0d act_words=%0d",
                 mismatch_count, OUTPUT_WORDS, mon_act_count);
        if (mismatch_count != 0) $fatal(1, "Gate F fast full first-CONV mismatch_count=%0d", mismatch_count);

        $display("== GATE F FAST FULL FIRST-CONV TRUE SYSTOLIC PASS ==");
        $finish;
    end
endmodule
