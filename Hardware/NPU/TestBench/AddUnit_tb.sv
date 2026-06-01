`include "define.svh"

module AddUnit_tb;
    logic [7:0] lhs_u8;
    logic [7:0] rhs_u8;
    logic [5:0] lhs_shift;
    logic [5:0] rhs_shift;
    logic signed [8:0] lhs_signed;
    logic signed [8:0] rhs_signed;
    logic signed [18:0] sum_signed;
    logic [7:0] out_u8;

    int checks;
    int errors;

    AddUnit dut (
        .lhs_u8(lhs_u8),
        .rhs_u8(rhs_u8),
        .lhs_shift(lhs_shift),
        .rhs_shift(rhs_shift),
        .lhs_signed(lhs_signed),
        .rhs_signed(rhs_signed),
        .sum_signed(sum_signed),
        .out_u8(out_u8)
    );

    function automatic int signed ref_signed(input int unsigned v);
        ref_signed = int'(v) - 128;
    endfunction

    function automatic int unsigned ref_add(
        input int unsigned lhs,
        input int unsigned rhs,
        input int unsigned lsh,
        input int unsigned rsh
    );
        int signed lhs_s;
        int signed rhs_s;
        int signed sum;
        begin
            lhs_s = ref_signed(lhs) >>> lsh;
            rhs_s = ref_signed(rhs) >>> rsh;
            sum = lhs_s + rhs_s;
            if (sum > 127) sum = 127;
            else if (sum < -128) sum = -128;
            ref_add = sum + 128;
        end
    endfunction

    task automatic check_case(
        input string name,
        input int unsigned lhs,
        input int unsigned rhs,
        input int unsigned lsh,
        input int unsigned rsh,
        input int unsigned exp
    );
        begin
            lhs_u8    = lhs[7:0];
            rhs_u8    = rhs[7:0];
            lhs_shift = lsh[5:0];
            rhs_shift = rsh[5:0];
            #1;
            checks++;
            if (out_u8 !== exp[7:0]) begin
                errors++;
                $display("  FAIL: %s lhs=%0d rhs=%0d lsh=%0d rsh=%0d got=%0d expected=%0d sum=%0d",
                         name, lhs, rhs, lsh, rsh, out_u8, exp, sum_signed);
            end else begin
                $display("  PASS: %s", name);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        $display("== AddUnit_tb ==");

        check_case("zero plus zero", 128, 128, 0, 0, 128);
        check_case("positive saturation", 255, 255, 0, 0, 255);
        check_case("negative saturation", 0, 0, 0, 0, 0);
        check_case("opposite signs", 255, 0, 0, 0, 127);
        check_case("lhs/rhs shifted differently", 0, 255, 1, 2, 95);
        check_case("mixed shifted positive result", 64, 200, 2, 1, 148);
        check_case("small exact cancellation", 129, 127, 0, 0, 128);
        check_case("both operands shifted", 130, 130, 1, 1, 130);

        for (int lhs = 0; lhs <= 255; lhs += 17) begin
            for (int rhs = 0; rhs <= 255; rhs += 31) begin
                for (int sh = 0; sh < 4; sh++) begin
                    check_case("sweep", lhs, rhs, sh, 3 - sh, ref_add(lhs, rhs, sh, 3 - sh));
                end
            end
        end

        if (errors == 0) begin
            $display("== AddUnit_tb PASS: %0d checks ==", checks);
            $finish;
        end
        $fatal(1, "AddUnit_tb FAIL: %0d/%0d checks failed", errors, checks);
    end
endmodule
