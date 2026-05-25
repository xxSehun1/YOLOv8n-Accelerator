`timescale 1ns/1ps
`include "define.svh"
// NPU_top_tb: integration smoke test for the NPU.
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
//   npu_program.hex      6-instruction test program (gen_test_program.py)
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

    always_ff @(posedge clk) begin
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
    always @(posedge clk) begin
        if (!rst) begin
            hb_cnt++;
            if (hb_cnt % 1000 == 0) begin
                $display("[%0t] pc=%0d halt=%0b cfg=%0b  ppc_st=%0d  wb_d=%0b iob_in_d=%0b iob_out_d=%0b  exec_v=%0b exec_d=%0b | ifmap_en=%0b lb_ifmap_v=%0b ifmap_rdy=%0b filter_rdy=%0b | pe00_st=%0d | oc_st=%0d ll=%0b lls=%0b dp=%0b pv=%0b",
                    $time, dut.pc, halted, dut.cfg_done,
                    dut.i_ppc.state,
                    dut.wb_fill_done, dut.iob_in_done, dut.iob_out_done,
                    dut.exec_valid, dut.exec_done,
                    dut.ifmap_en, dut.lb_ifmap_valid,
                    dut.GLB_ifmap_ready, dut.GLB_filter_ready,
                    dut.i_pe_array.ROW[0].COL[0].pe_inst.state,
                    dut.i_oc.state,
                    dut.oc_layer_last,
                    dut.i_oc.layer_last_seen,
                    dut.i_oc.drain_pending,
                    dut.i_oc.pack_valid);
            end
        end
    end

    // v3 test setup: real 3x3 conv on 4x4 input -> 2x2 output.
    //   Input  : pixel (1,1) channel 0 = 0x81 (+1 after zp), rest = 0x80
    //   Weights: all +1 (every byte = 0x01) packed as 36 words (4 OC x 4 IC x 9)
    //   Expected (sum over 3x3 window x 4 IC for each output channel):
    //     OUT[0][0] = window covering input rows 0..2 cols 0..2 -> includes (1,1)
    //                 -> 1 non-zero contribution per IC -> 1*4=4 per OC,
    //                 -> uint8 = 0x80 + 4 = 0x84
    //     OUT[0][1] = window rows 0..2 cols 1..3 -> includes (1,1) -> 4 -> 0x84
    //     OUT[1][0] = window rows 1..3 cols 0..2 -> includes (1,1) -> 4 -> 0x84
    //     OUT[1][1] = window rows 1..3 cols 1..3 -> includes (1,1) -> 4 -> 0x84
    //   All 4 output pixels x 4 channels = byte 0x84.
    //   Packed: each output word holds 4 channels for one pixel = 0x84848484.
    initial begin
        for (int i = 0; i < 1024; i++) begin
            dram_in_mem [i] = 32'h80808080;
            dram_out_mem[i] = 32'h00000000;
            dram_wgt_mem[i] = 32'h00000000;
        end

        // Input pixel (1,1) ALL 4 channels = 0x81 (+1 after zp=128). Index = 1*4+1 = 5.
        // All 4 IC must be non-zero so each IC contributes 1 to the MAC,
        // giving psum = 4 per output channel -> uint8 = 128+4 = 0x84.
        // (Was 32'h80808081: only IC=0 was +1, giving psum=1 -> 0x81 != 0x84.)
        dram_in_mem[5] = 32'h81818181;

        // 4 OC x 4 IC x 9 = 36 weight words, all = +1 in every byte.
        for (int i = 0; i < 36; i++) dram_wgt_mem[i] = 32'h01010101;
    end

    initial begin
        $display("== NPU_top integration smoke test (1x1 synthetic conv) ==");

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

        // Dump output region (4 words for OUT=2x2 x 4 OC packed).
        $display("== Output region (DRAM 0x0020_0000 .. +16 bytes) ==");
        for (int i = 0; i < 4; i++) begin
            $display("   word[%0d] = 0x%08h  expect 0x84848484",
                     i, dram_out_mem[i]);
        end

        // Bit-exact check: all 4 output words = 0x84848484.
        begin
            int n_ok = 0;
            for (int i = 0; i < 4; i++)
                if (dram_out_mem[i] === 32'h84848484) n_ok++;
            $display("== sanity: %0d / 4 output words match golden ==", n_ok);
            if (n_ok == 4)
                $display("== >>>>>>>>>>>  BIT-EXACT PASS  <<<<<<<<<<< ==");
            else
                $display("== >>>>>>>>>>>  PARTIAL / MISMATCH  <<<<<<<<<<< ==");
        end

        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "NPU_top_tb global TIMEOUT");
    end

endmodule
