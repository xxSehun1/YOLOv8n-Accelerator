module GON_Bus #(
    parameter NUMS_MASTER = `NUMS_PE_COL,
    parameter ID_SIZE = `XID_BITS
) (
    input clk,
    input rst,
    input [ID_SIZE - 1:0] tag,

    input [NUMS_MASTER - 1:0] master_valid,
    input [NUMS_MASTER * `DATA_BITS - 1:0] master_data,
    output logic [NUMS_MASTER - 1:0] master_ready,

    output logic slave_valid,
    input slave_ready,
    output logic [`DATA_BITS - 1:0] slave_data,

    // Config
    input set_id,
    input [ID_SIZE - 1:0] ID_scan_in,
    output logic [ID_SIZE - 1 :0] ID_scan_out
 );
/* TODO: Start writing your implementation here */

    assign slave_valid = |master_valid;
    assign master_ready = {NUMS_MASTER{slave_ready}};

    always_comb begin
        slave_data = '0; 
        for (int i = 0; i < NUMS_MASTER; i = i + 1) begin
            if (master_valid[i]) begin
                slave_data = master_data[i * `DATA_BITS +: `DATA_BITS];
                
            end
        end
    end

    assign ID_scan_out = ID_scan_in;

/* TODO: End of implementation */
endmodule
