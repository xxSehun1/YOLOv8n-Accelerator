module Maxpool_Qint8 (
    input clk,
    input rst,
    input en,
    input init,
    input logic [7:0] data_in,
    output logic [7:0] data_out
);
/* TODO: Start writing your implementation here */

    logic [7:0] max_val;
    logic [7:0] max_next;

    always_ff@(posedge clk) begin
        if(rst)  begin
            max_val <= 8'b1000_0000;
        end else begin
            max_val <= max_next;
        end
    end

    always_comb begin
        if(init == 1) begin 
            max_next = data_in;
        end else if (en == 1) begin 
            if ($signed(data_in) > $signed(max_val)) begin
                max_next = data_in;
            end else begin
                max_next = max_val;
            end
        end else begin
            max_next = max_val;
        end
    end

    assign data_out = max_next;

/* TODO: End of implementation */
endmodule
