`timescale 1ns/1ps
`include "define.svh"

module NPU_gate_f_first_conv_tb;
    localparam int CLK_HALF = 5;

    localparam logic [31:0] DRAM_INPUT_BASE  = 32'h0000_0000;
    localparam logic [31:0] DRAM_WEIGHT_BASE = 32'h0100_0000;

    localparam int IN_H = 640;
    localparam int IN_W = 640;
    localparam int IN_C = 3;
    localparam int OUT_H = 320;
    localparam int OUT_W = 320;
    localparam int OUT_C = 16;

    localparam int INPUT_BYTES  = IN_H * IN_W * IN_C;
    localparam int OUTPUT_BYTES = OUT_H * OUT_W * OUT_C;
    localparam int WEIGHT_BYTES = 2 * 1024 * 1024;

    localparam int INPUT_WORDS  = INPUT_BYTES / 4;
    localparam int OUTPUT_WORDS = OUTPUT_BYTES / 4;
    localparam int WEIGHT_WORDS = WEIGHT_BYTES / 4;

    localparam logic [31:0] FIRST_OUT_SRAM = 32'h0012_C000;

    logic clk = 1'b0;
    logic rst;
    logic start;
    logic halted;

    logic dram_en;
    logic dram_we;
    logic [31:0]           dram_addr;
    logic [`DATA_BITS-1:0] dram_wdata;
    logic [`DATA_BITS-1:0] dram_rdata;

    logic [`DATA_BITS-1:0] dram_in_mem  [0:INPUT_WORDS-1];
    logic [`DATA_BITS-1:0] dram_wgt_mem [0:WEIGHT_WORDS-1];
    byte unsigned input_bytes  [0:INPUT_BYTES-1];
    byte unsigned weight_bytes [0:WEIGHT_BYTES-1];
    byte unsigned golden_bytes [0:OUTPUT_BYTES-1];

    int cycle;
    int mon_filter_count;
    int mon_lb_count;
    int mon_win_count;
    int mon_opsum_count;
    int mon_act_count;

    NPU_top dut (
        .clk(clk), .rst(rst), .start(start), .halted(halted),
        .dram_en(dram_en), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata), .dram_rdata(dram_rdata)
    );

    always #CLK_HALF clk = ~clk;

    function automatic bit in_input_region(input logic [31:0] addr);
        in_input_region = (addr >= DRAM_INPUT_BASE)
                       && (addr <  DRAM_INPUT_BASE + INPUT_BYTES);
    endfunction

    function automatic bit in_weight_region(input logic [31:0] addr);
        in_weight_region = (addr >= DRAM_WEIGHT_BASE)
                        && (addr <  DRAM_WEIGHT_BASE + WEIGHT_BYTES);
    endfunction

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

    always @(posedge clk) begin
        if (dram_en) begin
            if (in_weight_region(dram_addr)) begin
                if (dram_we) $fatal(1, "Unexpected write to weight DRAM addr=0x%08h", dram_addr);
                dram_rdata <= dram_wgt_mem[(dram_addr - DRAM_WEIGHT_BASE) >> 2];
            end else if (in_input_region(dram_addr)) begin
                if (dram_we) $fatal(1, "Unexpected write to input DRAM addr=0x%08h", dram_addr);
                dram_rdata <= dram_in_mem[(dram_addr - DRAM_INPUT_BASE) >> 2];
            end else begin
                dram_rdata <= '0;
                if (dram_we) begin
                    $display("[MON][DRAM_WR][%0t] addr=0x%08h data=0x%08h",
                             $time, dram_addr, dram_wdata);
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
            mon_filter_count <= 0;
            mon_lb_count <= 0;
            mon_win_count <= 0;
            mon_opsum_count <= 0;
            mon_act_count <= 0;
        end else begin
            cycle <= cycle + 1;

            if ((cycle % 100000) == 0) begin
                $display("[HB][%0t] cyc=%0d pc=%0d ppc_st=%0d tile_base=%0d tile_w=%0d tile_start=%0b ifcnt=%0d oy=%0d opsum=%0d halted=%0b",
                         $time, cycle, dut.pc, dut.i_ppc.state,
                         dut.i_ppc.strip_ow_base, dut.i_ppc.strip_w,
                         dut.pe_tile_start,
                         dut.i_ppc.ifmap_count, dut.i_ppc.ifmap_oy,
                         dut.i_ppc.opsum_count, halted);
            end

            if (dut.GLB_filter_valid && dut.GLB_filter_ready && dut.glb_sel == 2'd1) begin
                if (mon_filter_count < 12) begin
                    $display("[MON][FILTER][%0t] n=%0d tagX=%0d data=0x%08h",
                             $time, mon_filter_count, dut.filter_tag_X, dut.GLB_data_in);
                end
                mon_filter_count++;
            end

            if (dut.lb_ifmap_valid && dut.lb_ifmap_ready) begin
                if (mon_lb_count < 12) begin
                    $display("[MON][LB_IN][%0t] n=%0d data=0x%08h",
                             $time, mon_lb_count, dut.lb_ifmap_data);
                end
                mon_lb_count++;
            end

            if (dut.GLB_ifmap_valid && dut.GLB_ifmap_ready && dut.glb_sel == 2'd0) begin
                if (mon_win_count >= 2997 && mon_win_count <= 3005) begin
                    $display("[DBG][TARGET_WIN][%0t] n=%0d tagX=%0d data=0x%08h",
                             $time, mon_win_count, dut.ifmap_tag_X, dut.GLB_data_in);
                end
                mon_win_count++;
            end

            if (dut.GLB_opsum_valid_to_oc && dut.GLB_opsum_ready && dut.glb_sel == 2'd3) begin
                if (mon_opsum_count < 16) begin
                    $display("[MON][OPSUM][%0t] n=%0d ow=%0d oc=%0d data=%0d",
                             $time, mon_opsum_count, dut.i_ppc.opsum_ow,
                             dut.i_ppc.opsum_oc, $signed(dut.GLB_data_out));
                end
                if (mon_opsum_count >= 5324 && mon_opsum_count <= 5332) begin
                    $display("[DBG][TARGET_OPSUM][%0t] n=%0d pixel=%0d row=%0d ow=%0d oc=%0d data=%0d",
                             $time, mon_opsum_count, mon_opsum_count / OUT_C,
                             dut.i_ppc.ifmap_oy, dut.i_ppc.opsum_ow,
                             dut.i_ppc.opsum_oc, $signed(dut.GLB_data_out));
                end
                mon_opsum_count++;
            end

            if (dut.oc_act_valid && dut.oc_act_ready) begin
                if (mon_act_count < 16) begin
                    $display("[MON][ACT][%0t] n=%0d data=0x%08h",
                             $time, mon_act_count, dut.oc_act_data);
                end
                if (mon_act_count >= 1328 && mon_act_count <= 1334) begin
                    $display("[DBG][TARGET_ACT][%0t] n=%0d pixel=%0d group=%0d data=0x%08h exp=0x%08h ppu_in=%0d ppu_out=0x%02h",
                             $time, mon_act_count, mon_act_count >> 2,
                             mon_act_count & 3, dut.oc_act_data,
                             golden_act_word(mon_act_count),
                             $signed(dut.oc_ppu_data_in), dut.oc_ppu_data_out);
                end
                if (dut.oc_act_data !== golden_act_word(mon_act_count)) begin
                    $fatal(1, "[ACT_MISMATCH] n=%0d got=0x%08h exp=0x%08h",
                           mon_act_count, dut.oc_act_data, golden_act_word(mon_act_count));
                end
                mon_act_count++;
            end
        end
    end

    task automatic load_input;
        int fd;
        int nread;
        begin
            fd = $fopen("../../../Build/input_seed0.bin", "rb");
            if (fd == 0) $fatal(1, "Cannot open ../../../Build/input_seed0.bin");
            nread = $fread(input_bytes, fd);
            $fclose(fd);
            if (nread != INPUT_BYTES) $fatal(1, "input size got %0d expected %0d", nread, INPUT_BYTES);
            for (int i = 0; i < INPUT_BYTES; i += 4) begin
                dram_in_mem[i >> 2] = {input_bytes[i + 3],
                                       input_bytes[i + 2],
                                       input_bytes[i + 1],
                                       input_bytes[i]};
            end
            $display("[TB] loaded input bytes=%0d", nread);
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
            for (int i = 0; i < WEIGHT_WORDS; i++) dram_wgt_mem[i] = '0;
            for (int i = 0; i < nread; i += 4) begin
                dram_wgt_mem[i >> 2] = {
                    (i + 3 < nread) ? weight_bytes[i + 3] : 8'h00,
                    (i + 2 < nread) ? weight_bytes[i + 2] : 8'h00,
                    (i + 1 < nread) ? weight_bytes[i + 1] : 8'h00,
                    weight_bytes[i]
                };
            end
            $display("[TB] loaded weight bytes=%0d", nread);
        end
    endtask

    task automatic load_golden;
        int fd;
        int nread;
        begin
            fd = $fopen("../../../Build/golden_l0_conv.bin", "rb");
            if (fd == 0) $fatal(1, "Cannot open ../../../Build/golden_l0_conv.bin");
            nread = $fread(golden_bytes, fd);
            $fclose(fd);
            if (nread != OUTPUT_BYTES) $fatal(1, "golden size got %0d expected %0d", nread, OUTPUT_BYTES);
            $display("[TB] loaded golden bytes=%0d", nread);
        end
    endtask

    initial begin
        load_input();
        load_weights();
        load_golden();
    end

    initial begin
        int mismatch_count;
        logic [31:0] got_word;
        logic [31:0] exp_word;

        $display("== Gate F TRUE systolic full first-CONV check ==");

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
                $display("[TB] HALT observed at %0t cycle=%0d", $time, cycle);
            end
            begin
                repeat (200_000_000) @(posedge clk);
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

        $display("[RESULT] mismatch_count=%0d output_words=%0d", mismatch_count, OUTPUT_WORDS);
        if (mismatch_count != 0) $fatal(1, "Gate F full first-CONV mismatch_count=%0d", mismatch_count);

        $display("== GATE F FULL FIRST-CONV TRUE SYSTOLIC PASS ==");
        $finish;
    end

endmodule
