`include "define.svh"

module ActivationUnit_tb;
    localparam int ACC_WIDTH = 64;

    logic signed [ACC_WIDTH-1:0] q_in;
    logic [11:0] flags;
    logic signed [ACC_WIDTH-1:0] q_out;

    int checks;
    int errors;

    ActivationUnit #(.ACC_WIDTH(ACC_WIDTH)) dut (
        .q_in(q_in),
        .flags(flags),
        .q_out(q_out)
    );

    function automatic logic signed [ACC_WIDTH-1:0] ref_round_nearest_even(input real x);
        real abs_x;
        real floor_abs;
        real frac;
        longint signed mag;
        longint signed rounded_mag;
        bit neg;
        begin
            neg       = (x < 0.0);
            abs_x     = neg ? -x : x;
            floor_abs = $floor(abs_x);
            mag       = $rtoi(floor_abs);
            frac      = abs_x - floor_abs;
            if (frac > 0.5) rounded_mag = mag + 1;
            else if (frac < 0.5) rounded_mag = mag;
            else rounded_mag = ((mag % 2) == 0) ? mag : (mag + 1);
            ref_round_nearest_even = neg ? -rounded_mag : rounded_mag;
        end
    endfunction

    function automatic logic signed [ACC_WIDTH-1:0] ref_activation(
        input logic signed [ACC_WIDTH-1:0] q,
        input logic [11:0] f
    );
        real q_real;
        real q_clip_real;
        real sigmoid;
        begin
            if (f[`FLAG_SIGMOID] && f[`FLAG_MULTIPLY]) begin
                q_real = q;
                if (q < -64'sd30) q_clip_real = -30.0;
                else if (q > 64'sd30) q_clip_real = 30.0;
                else q_clip_real = q;
                sigmoid = 1.0 / (1.0 + $exp(-q_clip_real));
                ref_activation = ref_round_nearest_even(q_real * sigmoid);
            end else if (f[`FLAG_RELU]) begin
                ref_activation = (q < 0) ? 0 : q;
            end else begin
                ref_activation = q;
            end
        end
    endfunction

    task automatic check_case(
        input string name,
        input logic signed [ACC_WIDTH-1:0] q,
        input logic [11:0] f,
        input logic signed [ACC_WIDTH-1:0] exp
    );
        begin
            q_in  = q;
            flags = f;
            #1;
            checks++;
            if (q_out !== exp) begin
                errors++;
                $display("  FAIL: %s q=%0d flags=0x%03h got=%0d expected=%0d",
                         name, q, f, q_out, exp);
            end else begin
                $display("  PASS: %s", name);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        $display("== ActivationUnit_tb ==");

        check_case("no activation keeps negative value", -64'sd200, 12'h000, -64'sd200);
        check_case("bias-only flag does not change activation", 64'sd42, 12'h008, 64'sd42);
        check_case("relu clamps negative", -64'sd5, 12'h004, 64'sd0);
        check_case("relu keeps positive", 64'sd7, 12'h004, 64'sd7);

        check_case("SiLU negative large rounds to zero", -64'sd128, 12'h003, 64'sd0);
        check_case("SiLU negative small rounds to zero", -64'sd1, 12'h003, 64'sd0);
        check_case("SiLU zero", 64'sd0, 12'h003, 64'sd0);
        check_case("SiLU positive one", 64'sd1, 12'h003, 64'sd1);
        check_case("SiLU positive clipped sigmoid", 64'sd127, 12'h003, 64'sd127);
        check_case("FLAGS=0x00b follows SiLU path", 64'sd16, 12'h00b, 64'sd16);

        for (int q = -128; q <= 127; q++) begin
            check_case("sweep no activation", q, 12'h000, ref_activation(q, 12'h000));
            check_case("sweep relu", q, 12'h004, ref_activation(q, 12'h004));
            check_case("sweep silu", q, 12'h00b, ref_activation(q, 12'h00b));
        end

        if (errors == 0) begin
            $display("== ActivationUnit_tb PASS: %0d checks ==", checks);
            $finish;
        end
        $fatal(1, "ActivationUnit_tb FAIL: %0d/%0d checks failed", errors, checks);
    end
endmodule
