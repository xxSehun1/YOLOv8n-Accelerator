`include "define.svh"
module PostQuant (
    input [`DATA_BITS-1:0] data_in,
    input [5:0] scaling_factor,
    output logic [7:0] data_out
);
/* TODO: Start writing your implementation here */

    logic signed [`DATA_BITS-1: 0] shift_val;
    logic signed [`DATA_BITS-1:0] signed_in;


    always_comb begin
        signed_in = $signed(data_in);
        shift_val = signed_in >>> scaling_factor;

        if (shift_val > 32'sd127) begin
            data_out = 8'h7F;
        end else if (shift_val < -32'sd128) begin
            data_out = 8'h80;
        end else begin
            data_out = shift_val[7:0];
        end

    end



/* TODO: End of implementation */
endmodule
