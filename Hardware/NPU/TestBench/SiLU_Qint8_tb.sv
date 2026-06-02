`timescale 1ns/1ps
`include "define.svh"

module SiLU_Qint8_tb;
    logic en;
    logic signed [7:0] data_in;
    logic signed [7:0] data_out;

    SiLU_Qint8 dut (
        .en(en),
        .data_in(data_in),
        .data_out(data_out)
    );

    function automatic int round_nearest_even(input real x);
        real abs_x;
        real floor_abs;
        real frac;
        int mag;
        int rounded_mag;
        bit neg;
        begin
            neg = (x < 0.0);
            abs_x = neg ? -x : x;
            floor_abs = $floor(abs_x);
            mag = $rtoi(floor_abs);
            frac = abs_x - floor_abs;

            if (frac > 0.5) begin
                rounded_mag = mag + 1;
            end else if (frac < 0.5) begin
                rounded_mag = mag;
            end else begin
                rounded_mag = ((mag % 2) == 0) ? mag : (mag + 1);
            end

            round_nearest_even = neg ? -rounded_mag : rounded_mag;
        end
    endfunction

    function automatic logic signed [7:0] silu_ref(input logic signed [7:0] q8);
        int q;
        real q_clip;
        real sigmoid;
        int y;
        begin
            q = q8;
            if (q < -30) begin
                q_clip = -30.0;
            end else if (q > 30) begin
                q_clip = 30.0;
            end else begin
                q_clip = q;
            end

            sigmoid = 1.0 / (1.0 + $exp(-q_clip));
            y = round_nearest_even(q * sigmoid);
            if (y > 127) y = 127;
            else if (y < -128) y = -128;
            silu_ref = y[7:0];
        end
    endfunction

    initial begin
        logic [7:0] raw;
        logic signed [7:0] expected;
        int fail_count;

        fail_count = 0;
        $display("== SiLU_Qint8 LUT exhaustive test ==");

        en = 1'b1;
        for (int i = 0; i < 256; i++) begin
            raw = i[7:0];
            data_in = raw;
            #1;
            expected = silu_ref(data_in);
            if (data_out !== expected) begin
                $display("FAIL LUT raw=0x%02h q=%0d got=%0d expected=%0d",
                         raw, data_in, data_out, expected);
                fail_count++;
            end
        end

        en = 1'b0;
        for (int i = 0; i < 256; i++) begin
            raw = i[7:0];
            data_in = raw;
            #1;
            if (data_out !== data_in) begin
                $display("FAIL passthrough raw=0x%02h got=%0d expected=%0d",
                         raw, data_out, data_in);
                fail_count++;
            end
        end

        if (fail_count != 0) begin
            $fatal(1, "SiLU_Qint8_tb FAILED with %0d mismatches", fail_count);
        end

        $display("== SiLU_Qint8_tb PASS: 256 LUT entries and passthrough matched ==");
        $finish;
    end
endmodule

