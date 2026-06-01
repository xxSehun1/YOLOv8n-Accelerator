`include "define.svh"

module QuantizeUnit_tb;
    localparam int ACC_WIDTH = 64;

    logic signed [ACC_WIDTH-1:0] acc_in;
    logic [5:0] shift;
    logic signed [ACC_WIDTH-1:0] shifted_signed;
    logic signed [7:0] clipped_signed;
    logic [7:0] packed_u8;

    int checks;
    int errors;

    QuantizeUnit #(.ACC_WIDTH(ACC_WIDTH)) dut (
        .acc_in(acc_in),
        .shift(shift),
        .shifted_signed(shifted_signed),
        .clipped_signed(clipped_signed),
        .packed_u8(packed_u8)
    );

    task automatic check_case(
        input string name,
        input logic signed [ACC_WIDTH-1:0] acc,
        input int sh,
        input logic signed [ACC_WIDTH-1:0] exp_shifted,
        input logic signed [7:0] exp_clipped,
        input logic [7:0] exp_packed
    );
        begin
            acc_in = acc;
            shift  = sh[5:0];
            #1;
            checks++;
            if (shifted_signed !== exp_shifted ||
                clipped_signed !== exp_clipped ||
                packed_u8 !== exp_packed) begin
                errors++;
                $display("  FAIL: %s acc=%0d shift=%0d got shifted=%0d clipped=%0d packed=%0d expected shifted=%0d clipped=%0d packed=%0d",
                         name, acc, sh, shifted_signed, clipped_signed, packed_u8,
                         exp_shifted, exp_clipped, exp_packed);
            end else begin
                $display("  PASS: %s", name);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        $display("== QuantizeUnit_tb ==");

        check_case("zero maps to zero-point", 64'sd0, 0, 64'sd0, 8'sd0, 8'd128);
        check_case("positive max no saturation", 64'sd127, 0, 64'sd127, 8'sd127, 8'd255);
        check_case("positive overflow saturates", 64'sd128, 0, 64'sd128, 8'sd127, 8'd255);
        check_case("negative min no saturation", -64'sd128, 0, -64'sd128, -8'sd128, 8'd0);
        check_case("negative overflow saturates", -64'sd129, 0, -64'sd129, -8'sd128, 8'd0);
        check_case("positive shift then saturation", 64'sd1024, 3, 64'sd128, 8'sd127, 8'd255);
        check_case("negative arithmetic shift then min", -64'sd1024, 3, -64'sd128, -8'sd128, 8'd0);
        check_case("rounding boundary is truncating shift", 64'sd511, 2, 64'sd127, 8'sd127, 8'd255);
        check_case("negative shift floors by arithmetic shift", -64'sd513, 2, -64'sd129, -8'sd128, 8'd0);

        for (int sh = 0; sh < 64; sh++) begin
            check_case("all supported shifts preserve -1", -64'sd1, sh, -64'sd1, -8'sd1, 8'd127);
        end

        if (errors == 0) begin
            $display("== QuantizeUnit_tb PASS: %0d checks ==", checks);
            $finish;
        end
        $fatal(1, "QuantizeUnit_tb FAIL: %0d/%0d checks failed", errors, checks);
    end
endmodule
