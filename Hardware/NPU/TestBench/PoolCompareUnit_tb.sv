`include "define.svh"

module PoolCompareUnit_tb;
    logic current_valid;
    logic [7:0] current_max_u8;
    logic candidate_valid;
    logic candidate_is_pad;
    logic [7:0] candidate_u8;
    logic max_valid;
    logic [7:0] max_u8;
    logic signed [8:0] current_signed;
    logic signed [8:0] candidate_signed;

    int checks;
    int errors;

    PoolCompareUnit dut (
        .current_valid(current_valid),
        .current_max_u8(current_max_u8),
        .candidate_valid(candidate_valid),
        .candidate_is_pad(candidate_is_pad),
        .candidate_u8(candidate_u8),
        .max_valid(max_valid),
        .max_u8(max_u8),
        .current_signed(current_signed),
        .candidate_signed(candidate_signed)
    );

    task automatic check_case(
        input string name,
        input bit cur_valid,
        input int unsigned cur,
        input bit cand_valid,
        input bit cand_pad,
        input int unsigned cand,
        input bit exp_valid,
        input int unsigned exp
    );
        begin
            current_valid   = cur_valid;
            current_max_u8  = cur[7:0];
            candidate_valid = cand_valid;
            candidate_is_pad = cand_pad;
            candidate_u8    = cand[7:0];
            #1;
            checks++;
            if (max_valid !== exp_valid || max_u8 !== exp[7:0]) begin
                errors++;
                $display("  FAIL: %s cur_valid=%0d cur=%0d cand_valid=%0d pad=%0d cand=%0d got valid=%0d max=%0d expected valid=%0d max=%0d",
                         name, cur_valid, cur, cand_valid, cand_pad, cand,
                         max_valid, max_u8, exp_valid, exp);
            end else begin
                $display("  PASS: %s", name);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        $display("== PoolCompareUnit_tb ==");

        check_case("first candidate initializes max", 0, 0, 1, 0, 128, 1, 128);
        check_case("candidate higher in signed domain wins", 1, 127, 1, 0, 128, 1, 128);
        check_case("current higher stays", 1, 200, 1, 0, 64, 1, 200);
        check_case("padding contributes uint8 zero", 0, 0, 1, 1, 255, 1, 0);
        check_case("padding loses against real current", 1, 10, 1, 1, 255, 1, 10);
        check_case("candidate invalid keeps current", 1, 42, 0, 0, 255, 1, 42);
        check_case("no valid input remains invalid", 0, 0, 0, 0, 0, 0, 0);
        check_case("all equal keeps current", 1, 88, 1, 0, 88, 1, 88);
        check_case("top-left border pad then real pixel", 1, 0, 1, 0, 1, 1, 1);
        check_case("uint8 255 is signed +127", 1, 254, 1, 0, 255, 1, 255);

        if (errors == 0) begin
            $display("== PoolCompareUnit_tb PASS: %0d checks ==", checks);
            $finish;
        end
        $fatal(1, "PoolCompareUnit_tb FAIL: %0d/%0d checks failed", errors, checks);
    end
endmodule
