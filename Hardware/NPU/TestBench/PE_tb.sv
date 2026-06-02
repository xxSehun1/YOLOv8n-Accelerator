`timescale 1ns/1ps
`include "define.svh"
// PE_tb: single-PE testbench (instrumented / debug version).
//
// Drives one PE through IDLE -> WEIGHT -> IF -> COMPUTE -> SEND and checks the
// 3-tap row MAC against a golden reference.
//
// Every handshake wait is bounded: if the PE FSM does not progress within a
// cycle budget the test reports exactly which transition stalled, so a hang
// points straight at the broken state in PE.sv.
//
// Compile (run from Hardware/NPU/tb):
//   verilator --binary --timing -j 0 -Wno-fatal \
//             +incdir+.. +incdir+../pe_array \
//             ../pe_array/PE.sv PE_tb.sv --top-module PE_tb

// Bounded wait: spin until cond, at most 300 cycles, else report and abort.
`define EXPECT(cond, msg)                                                  \
    begin                                                                  \
        integer wt_; wt_ = 0;                                               \
        while (!(cond)) begin                                               \
            @(posedge clk); wt_ = wt_ + 1;                                  \
            if (wt_ > 300) begin                                            \
                $display("  >> STUCK: %s  (FSM did not progress)", msg);    \
                $fatal(1, "PE FSM stall");                                  \
            end                                                             \
        end                                                                \
    end

module PE_tb;

    logic clk = 0;
    logic rst, PE_en;
    logic [`CONFIG_SIZE-1:0] i_config;
    logic [`DATA_BITS-1:0]   ifmap, filter, ipsum, opsum;
    logic ifmap_valid, filter_valid, ipsum_valid, opsum_ready;
    logic ifmap_ready, filter_ready, ipsum_ready, opsum_valid;

    PE dut (
        .clk(clk), .rst(rst), .PE_en(PE_en), .i_config(i_config),
        .tile_start(1'b0),
        .ifmap(ifmap), .filter(filter), .ipsum(ipsum),
        .ifmap_valid(ifmap_valid), .filter_valid(filter_valid),
        .ipsum_valid(ipsum_valid), .opsum_ready(opsum_ready),
        .opsum(opsum),
        .ifmap_ready(ifmap_ready), .filter_ready(filter_ready),
        .ipsum_ready(ipsum_ready), .opsum_valid(opsum_valid)
    );

    always #5 clk = ~clk;

    int pass = 0, fail = 0;

    // Golden MAC, mirrors PE.sv.
    function automatic logic signed [31:0] mac_ref(
        input logic [31:0] w0, w1, w2, x0, x1, x2, ips);
        logic [31:0] w [0:2];
        logic [31:0] x [0:2];
        logic signed [31:0] acc;
        logic signed [8:0]  sx;
        logic signed [7:0]  sw;
        begin
            w[0]=w0; w[1]=w1; w[2]=w2;
            x[0]=x0; x[1]=x1; x[2]=x2;
            acc = $signed(ips);
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 4; j++) begin
                    sx  = $signed({1'b0, x[i][j*8 +: 8]}) - 9'sd128;
                    sw  = $signed(w[i][j*8 +: 8]);
                    acc = acc + sx * sw;
                end
            return acc;
        end
    endfunction

    task automatic run_case(
        input string       name,
        input logic [31:0] w0, w1, w2, x0, x1, x2, ips);
        logic signed [31:0] expected, got;
        begin
            $display("-- case '%s'", name);

            // Reset.
            rst = 1; PE_en = 0;
            filter_valid = 0; ifmap_valid = 0; ipsum_valid = 0; opsum_ready = 0;
            i_config = '0; ifmap = 0; filter = 0; ipsum = 0;
            repeat (3) @(posedge clk);
            rst = 0; PE_en = 1;
            $display("     reset released, PE_en=1");

            // WEIGHT.
            filter_valid = 1; filter = w0;
            `EXPECT(filter_ready === 1'b1, "IDLE -> WEIGHT (filter_ready)")
            $display("     WEIGHT reached, feeding 3 filter words");
            @(posedge clk); filter = w1;
            @(posedge clk); filter = w2;
            @(posedge clk); filter_valid = 0;

            // IF.
            ifmap_valid = 1; ifmap = x0;
            `EXPECT(ifmap_ready === 1'b1, "WEIGHT -> IF (ifmap_ready)")
            $display("     IF reached, feeding 3 ifmap words");
            @(posedge clk); ifmap = x1;
            @(posedge clk); ifmap = x2;
            @(posedge clk); ifmap_valid = 0;

            // COMPUTE.
            ipsum_valid = 1; ipsum = ips;
            `EXPECT(ipsum_ready === 1'b1, "IF -> COMPUTE (ipsum_ready)")
            $display("     COMPUTE reached, feeding ipsum");
            @(posedge clk);
            @(negedge clk);
            ipsum_valid = 0;
            ipsum = 0;

            // SEND.
            opsum_ready = 1;
            `EXPECT(opsum_valid === 1'b1, "COMPUTE -> SEND (opsum_valid)")
            $display("     SEND reached, capturing opsum");
            got = opsum;
            @(posedge clk);
            @(negedge clk);
            opsum_ready = 0;

            // Check.
            expected = mac_ref(w0, w1, w2, x0, x1, x2, ips);
            if (got === expected) begin
                $display("     PASS  opsum = %0d", got);
                pass++;
            end else begin
                $display("     FAIL  opsum = %0d  (expected %0d)", got, expected);
                fail++;
            end
        end
    endtask

    initial begin
        $display("== PE single-unit testbench (instrumented) ==");
        run_case("all+1 weights", 32'h01010101, 32'h01010101, 32'h01010101,
                                  32'h81818181, 32'h81818181, 32'h81818181, 32'd0);
        run_case("zero ifmap",    32'h01010101, 32'h01010101, 32'h01010101,
                                  32'h80808080, 32'h80808080, 32'h80808080, 32'd1000);
        run_case("neg weights",   32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF,
                                  32'h81818181, 32'h81818181, 32'h81818181, 32'd50);
        run_case("mixed",         32'h01FF02FE, 32'h0300FD04, 32'h05FB0600,
                                  32'h8A76FF01, 32'h80818283, 32'h7F857A90,
                                  -32'sd20);
        $display("== PE_tb done: %0d passed, %0d failed ==", pass, fail);
        if (fail != 0) $fatal(1, "PE testbench FAILED");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "PE_tb global TIMEOUT");
    end

endmodule
