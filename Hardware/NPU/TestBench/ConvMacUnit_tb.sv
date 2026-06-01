`include "define.svh"

module ConvMacUnit_tb;
    localparam int ACC_WIDTH = 64;

    logic [7:0] act_u8;
    logic signed [7:0] weight_s8;
    logic signed [ACC_WIDTH-1:0] psum_in;
    logic clear;
    logic add_bias;
    logic signed [31:0] bias_s32;
    logic signed [8:0] act_s9;
    logic signed [17:0] product_s18;
    logic signed [ACC_WIDTH-1:0] psum_out;

    int checks;
    int errors;

    ConvMacUnit #(.ACC_WIDTH(ACC_WIDTH)) dut (
        .act_u8(act_u8),
        .weight_s8(weight_s8),
        .psum_in(psum_in),
        .clear(clear),
        .add_bias(add_bias),
        .bias_s32(bias_s32),
        .act_s9(act_s9),
        .product_s18(product_s18),
        .psum_out(psum_out)
    );

    task automatic check_case(
        input string name,
        input int unsigned act,
        input int signed weight,
        input logic signed [ACC_WIDTH-1:0] psum,
        input bit do_clear,
        input bit do_bias,
        input int signed bias,
        input int signed exp_act,
        input int signed exp_product,
        input logic signed [ACC_WIDTH-1:0] exp_psum
    );
        begin
            act_u8    = act[7:0];
            weight_s8 = weight[7:0];
            psum_in   = psum;
            clear     = do_clear;
            add_bias  = do_bias;
            bias_s32  = bias;
            #1;
            checks++;
            if (act_s9 !== exp_act ||
                product_s18 !== exp_product ||
                psum_out !== exp_psum) begin
                errors++;
                $display("  FAIL: %s act=%0d weight=%0d psum=%0d clear=%0d bias_en=%0d bias=%0d got act_s=%0d product=%0d psum=%0d expected act_s=%0d product=%0d psum=%0d",
                         name, act, weight, psum, do_clear, do_bias, bias,
                         act_s9, product_s18, psum_out,
                         exp_act, exp_product, exp_psum);
            end else begin
                $display("  PASS: %s", name);
            end
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        $display("== ConvMacUnit_tb ==");

        check_case("zero-point activation has zero product",
                   128, 100, 64'sd5, 0, 0, 0,
                   0, 0, 64'sd5);
        check_case("positive activation times negative weight",
                   255, -2, 64'sd10, 0, 0, 0,
                   127, -254, -64'sd244);
        check_case("negative activation times negative weight from clear",
                   0, -128, 64'sd999, 1, 0, 0,
                   -128, 16384, 64'sd16384);
        check_case("bias is explicitly sign-extended and added",
                   129, 5, 64'sd100, 0, 1, -20,
                   1, 5, 64'sd85);
        check_case("clear plus bias starts from zero",
                   127, -3, 64'sd500, 1, 1, 10,
                   -1, 3, 64'sd13);
        check_case("large psum stays 64-bit",
                   255, 127, 64'sd2147483000, 0, 1, 1234,
                   127, 16129, 64'sd2147500363);

        if (errors == 0) begin
            $display("== ConvMacUnit_tb PASS: %0d checks ==", checks);
            $finish;
        end
        $fatal(1, "ConvMacUnit_tb FAIL: %0d/%0d checks failed", errors, checks);
    end
endmodule
