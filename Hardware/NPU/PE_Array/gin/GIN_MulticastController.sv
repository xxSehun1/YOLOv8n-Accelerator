module GIN_MulticastController #(
    parameter ID_SIZE = `XID_BITS
    )(
    input clk,
    input rst,

    input set_id,
    input [ID_SIZE - 1:0] id_in,
    output reg [ID_SIZE - 1:0] id,

    input [ID_SIZE - 1:0] tag,

    input valid_in,
    output logic valid_out,
    input ready_in,
    output logic ready_out
);
/* TODO: Start writing your implementation here */


    logic judge;
    logic [ID_SIZE - 1:0] id_reg;

    always_ff@(posedge clk) begin
        if (rst) begin
            id_reg <= '0;
        end else if (set_id) begin
            id_reg <= id_in;
        end
    end

    always_comb begin
        if(tag == id_reg) begin
            judge = 1'b1;
        end else begin
            judge = 1'b0;
        end
    end

    assign valid_out = judge ? valid_in : 1'b0;
    assign ready_out = judge ? ready_in : 1'b1;
    assign id = id_reg;

/* TODO: End of implementation */
endmodule
