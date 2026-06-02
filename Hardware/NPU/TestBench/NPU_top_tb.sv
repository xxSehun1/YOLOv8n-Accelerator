`timescale 1ns/1ps
`include "define.svh"
// NPU_top_tb: true-systolic micro smoke test for the NPU.
//
// Behavioural DRAM model split into three small regions (12 KiB total) by
// address decode to keep sim memory small and fast:
//   0x0000_0xxx  input feature map  (4 KiB)
//   0x0020_0xxx  output region      (4 KiB)
//   0x0100_0xxx  weights            (4 KiB)
//
// Initialises a synthetic 1x1 conv test, pulses start, waits for halted,
// then dumps the 16-word output region.
//
// Requires the following files in the cwd:
//   npu_program.hex      6-instruction micro Gate-F smoke program
//   shared_config.hex    Eyeriss scan-chain ROM     (gen_shared_hex.py)
module NPU_top_tb;

    logic clk = 0;
    logic rst, start;
    logic halted;
    logic dram_en, dram_we;
    logic [31:0]                  dram_addr;
    logic [`DATA_BITS-1:0]        dram_wdata;
    logic [`DATA_BITS-1:0]        dram_rdata;

    // Three DRAM regions of 1024 words (4 KiB) each.
    logic [`DATA_BITS-1:0] dram_in_mem  [0:1023];
    logic [`DATA_BITS-1:0] dram_out_mem [0:1023];
    logic [`DATA_BITS-1:0] dram_wgt_mem [0:1023];

    // Region select.
    logic in_sel, out_sel, wgt_sel;
    assign in_sel  = (dram_addr[31:24] == 8'h00) && (dram_addr[23:12] == 12'h000);
    assign out_sel = (dram_addr[31:24] == 8'h00) && (dram_addr[23:20] == 4'h2);
    assign wgt_sel = (dram_addr[31:24] == 8'h01);

    always @(posedge clk) begin
        if (dram_en) begin
            if (in_sel) begin
                if (dram_we) dram_in_mem[dram_addr[11:2]]  <= dram_wdata;
                dram_rdata <= dram_in_mem[dram_addr[11:2]];
            end else if (out_sel) begin
                if (dram_we) dram_out_mem[dram_addr[11:2]] <= dram_wdata;
                dram_rdata <= dram_out_mem[dram_addr[11:2]];
            end else if (wgt_sel) begin
                if (dram_we) dram_wgt_mem[dram_addr[11:2]] <= dram_wdata;
                dram_rdata <= dram_wgt_mem[dram_addr[11:2]];
            end
        end
    end

    NPU_top dut (.*);

    always #5 clk = ~clk;

    // Heartbeat: every 1000 cycles print key state to locate the stall.
    int hb_cnt = 0;
    int mon_filter_count = 0;
    int mon_ifmap_count = 0;
    int mon_lb_in_count = 0;
    int mon_ipsum_count = 0;
    int mon_opsum_count = 0;
    int mon_act_count = 0;
    int mon_sram_write_count = 0;
    int mon_dma_sram_write_count = 0;
    int mon_dram_store_count = 0;
    always @(posedge clk) begin
        if (!rst) begin
            hb_cnt++;
            if (hb_cnt % 1000 == 0) begin
                $display("[%0t] pc=%0d halt=%0b cfg=%0b  ppc_st=%0d  wb_d=%0b iob_in_d=%0b iob_out_d=%0b  exec_v=%0b exec_d=%0b | ifmap_en=%0b lb_ifmap_v=%0b ifmap_rdy=%0b filter_rdy=%0b | ifcnt=%0d ow=%0d oy=%0d tap_y=%0d tap_x=%0d tagX=%0d | pe00=%0d pe10=%0d pe20=%0d pe30=%0d | oc_st=%0d ll=%0b lls=%0b dp=%0b pv=%0b",
                    $time, dut.pc, halted, dut.cfg_done,
                    dut.i_ppc.state,
                    dut.wb_fill_done, dut.iob_in_done, dut.iob_out_done,
                    dut.exec_valid, dut.exec_done,
                    dut.ifmap_en, dut.lb_ifmap_valid,
                    dut.GLB_ifmap_ready, dut.GLB_filter_ready,
                    dut.i_ppc.ifmap_count,
                    dut.i_ppc.ifmap_ow,
                    dut.i_ppc.ifmap_oy,
                    dut.i_ppc.ifmap_tap_y,
                    dut.i_ppc.ifmap_tap_x,
                    dut.ifmap_tag_X,
                    dut.i_pe_array.ROW[0].COL[0].pe_inst.state,
                    dut.i_pe_array.ROW[1].COL[0].pe_inst.state,
                    dut.i_pe_array.ROW[2].COL[0].pe_inst.state,
                    dut.i_pe_array.ROW[3].COL[0].pe_inst.state,
                    dut.i_oc.state,
                    dut.oc_layer_last,
                    dut.i_oc.layer_last_seen,
                    dut.i_oc.drain_pending,
                    dut.i_oc.pack_valid);
            end
            if (dut.i_ppc.state == 4 && dut.i_ppc.ifmap_count < 20 && (hb_cnt % 50 == 0)) begin
                $display("[IFMAP_DBG][%0t] cnt=%0d ow=%0d oy=%0d tap_y=%0d tap_x=%0d tagX=%0d tagY=%0d lb_v=%0b glb_r=%0b pe00=%0d pe10=%0d pe20=%0d pe30=%0d",
                    $time,
                    dut.i_ppc.ifmap_count,
                    dut.i_ppc.ifmap_ow,
                    dut.i_ppc.ifmap_oy,
                    dut.i_ppc.ifmap_tap_y,
                    dut.i_ppc.ifmap_tap_x,
                    dut.ifmap_tag_X,
                    dut.ifmap_tag_Y,
                    dut.lb_win_valid,
                    dut.GLB_ifmap_ready,
                    dut.i_pe_array.ROW[0].COL[0].pe_inst.state,
                    dut.i_pe_array.ROW[1].COL[0].pe_inst.state,
                    dut.i_pe_array.ROW[2].COL[0].pe_inst.state,
                    dut.i_pe_array.ROW[3].COL[0].pe_inst.state);
            end

            if (dut.GLB_filter_valid && dut.GLB_filter_ready && dut.glb_sel == 2'd1) begin
                if (mon_filter_count < 16)
                    $display("[MON][FILTER][%0t] n=%0d tagX=%0d data=0x%08h sel=%0b wb0_fd=0x%08h wb1_fd=0x%08h sram_w0=0x%08h wb0_w0=0x%08h wb1_w0=0x%08h rd0=%0d rd1=%0d icg0=%0d k0=%0d ft0=%0d",
                             $time, mon_filter_count, dut.filter_tag_X, dut.GLB_data_in,
                             dut.wb_sel, dut.wb0_filter_data, dut.wb1_filter_data,
                             dut.i_sram.mem[32'h0038_0000 >> 2],
                             dut.wb0.mem[0], dut.wb1.mem[0],
                             dut.wb0.rd_idx, dut.wb1.rd_idx,
                             dut.wb0.ic_groups_l, dut.wb0.kernel_l, dut.wb0.filter_words_total_l);
                mon_filter_count++;
            end
            if (dut.lb_ifmap_valid && dut.lb_ifmap_ready) begin
                if (mon_lb_in_count < 16)
                    $display("[MON][LB_IN][%0t] n=%0d data=0x%08h",
                             $time, mon_lb_in_count, dut.lb_ifmap_data);
                mon_lb_in_count++;
            end
            if (dut.GLB_ifmap_valid && dut.GLB_ifmap_ready && dut.glb_sel == 2'd0) begin
                if (mon_ifmap_count < 24)
                    $display("[MON][IFMAP][%0t] n=%0d cnt=%0d tagX=%0d data=0x%08h",
                             $time, mon_ifmap_count, dut.i_ppc.ifmap_count,
                             dut.ifmap_tag_X, dut.GLB_data_in);
                mon_ifmap_count++;
            end
            if (dut.GLB_ipsum_valid && dut.GLB_ipsum_ready && dut.glb_sel == 2'd2) begin
                if (mon_ipsum_count < 12)
                    $display("[MON][IPSUM][%0t] n=%0d tagX=%0d lane=%0d",
                             $time, mon_ipsum_count, dut.ipsum_tag_X, dut.i_ppc.ipsum_oc);
                mon_ipsum_count++;
            end
            if (dut.GLB_opsum_valid_to_oc && dut.GLB_opsum_ready && dut.glb_sel == 2'd3) begin
                if (mon_opsum_count < 12)
                    $display("[MON][OPSUM][%0t] n=%0d tagX=%0d lane=%0d data=%0d",
                             $time, mon_opsum_count, dut.opsum_tag_X, dut.oc_lane_sel,
                             $signed(dut.GLB_data_out));
                mon_opsum_count++;
            end
            if (dut.oc_act_valid && dut.oc_act_ready) begin
                if (mon_act_count < 8)
                    $display("[MON][ACT][%0t] n=%0d data=0x%08h",
                             $time, mon_act_count, dut.oc_act_data);
                mon_act_count++;
            end
            if (dut.b_en && dut.b_we) begin
                if (mon_sram_write_count < 8)
                    $display("[MON][SRAM_WR][%0t] n=%0d addr=0x%08h data=0x%08h",
                             $time, mon_sram_write_count, dut.b_addr, dut.b_wdata);
                mon_sram_write_count++;
            end
            if (dut.a_en && dut.a_we) begin
                if (mon_dma_sram_write_count < 24 || dut.a_addr < 32'h0000_0100)
                    $display("[MON][DMA_SRAM_WR][%0t] n=%0d addr=0x%08h data=0x%08h",
                             $time, mon_dma_sram_write_count, dut.a_addr, dut.a_wdata);
                mon_dma_sram_write_count++;
            end
            if (dram_en && dram_we && out_sel) begin
                if (mon_dram_store_count < 8)
                    $display("[MON][DRAM_ST][%0t] n=%0d addr=0x%08h data=0x%08h",
                             $time, mon_dram_store_count, dram_addr, dram_wdata);
                mon_dram_store_count++;
            end
        end
    end

    // Micro Gate-F setup: real 3x3 conv on NCHW 4x3x4 input -> 4x1x2 output.
    //   Input  : pixel (1,1), all 4 channels = 0x81 (+1 after zp), rest = 0x80
    //   Weights: all +1 compact compiler layout [OC][IC][KH][KW]
    // Expected: every output channel sees one +1 per IC => psum=4 => uint8 0x84.
    initial begin
        for (int i = 0; i < 1024; i++) begin
            dram_in_mem [i] = 32'h80808080;
            dram_out_mem[i] = 32'h00000000;
            dram_wgt_mem[i] = 32'h00000000;
        end

        // NCHW flat offset = c*(H*W) + y*W + x, H=3, W=4, y=1, x=1.
        dram_in_mem[1][15:8]  = 8'h81; // c0 offset  5
        dram_in_mem[4][15:8]  = 8'h81; // c1 offset 17
        dram_in_mem[7][15:8]  = 8'h81; // c2 offset 29
        dram_in_mem[10][15:8] = 8'h81; // c3 offset 41

        // 4 OC x 4 IC x 9 = 36 weight words, all = +1 in every byte.
        for (int i = 0; i < 36; i++) dram_wgt_mem[i] = 32'h01010101;
    end

    initial begin
        $display("== NPU_top true-systolic micro Gate-F smoke test ==");

        rst = 1; start = 0;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // Pulse start.
        start = 1;
        @(posedge clk);
        start = 0;
        $display("   start asserted at %0t", $time);

        // Wait for halted with timeout.
        fork
            begin
                wait (halted === 1'b1);
                $display("   HALTED at %0t", $time);
            end
            begin
                #5_000_000;          // 5 ms timeout
                $display("   >> TIMEOUT (no halted in 5 ms sim time)");
                $fatal(1, "NPU did not halt");
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        // Dump and strictly check output region (NCHW 4x1x2 = 8 bytes).
        $display("== Output region (DRAM 0x0020_0000 .. +8 bytes) ==");
        for (int i = 0; i < 2; i++) begin
            $display("   word[%0d] = 0x%08h", i, dram_out_mem[i]);
        end

        if (dram_out_mem[0] !== 32'h8484_8484 || dram_out_mem[1] !== 32'h8484_8484) begin
            $fatal(1, "MICRO GOLDEN MISMATCH got word0=0x%08h word1=0x%08h expected both 0x84848484",
                   dram_out_mem[0], dram_out_mem[1]);
        end

        $display("== >>>>>>>>>>>  MICRO GOLDEN MATCH PASS  <<<<<<<<<<< ==");

        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "NPU_top_tb global TIMEOUT");
    end

endmodule
