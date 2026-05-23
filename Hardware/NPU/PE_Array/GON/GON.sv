`include "GON_Bus.sv"
`include "GON_MulticastController.sv"

module GON (
    input clk,
    input rst,

    /* Master GON <-> GLB */
    output logic GON_valid,
    input GON_ready,
    output logic [`DATA_BITS-1:0] GON_data,

    /* Controller <-> GON */
    input [`XID_BITS-1:0] tag_X,
    input [`YID_BITS-1:0] tag_Y,
    /* config */
    input set_XID,
    input [`XID_BITS - 1:0] XID_scan_in,

    input set_YID,
    input [`YID_BITS - 1:0] YID_scan_in,

    // Master PE <-> GON
    input [`NUMS_PE_ROW * `NUMS_PE_COL - 1:0] PE_valid,
    output logic [`NUMS_PE_ROW * `NUMS_PE_COL - 1:0] PE_ready,
    input [`DATA_BITS * `NUMS_PE_ROW * `NUMS_PE_COL - 1:0] PE_data

);
/* TODO: Start writing your implementation here */

    logic [`NUMS_PE_ROW-1:0] y_bus_master_valid;
    logic [`NUMS_PE_ROW-1:0] y_bus_master_ready;
    logic [`DATA_BITS*`NUMS_PE_ROW-1:0] y_bus_master_data;


    logic [`YID_BITS-1:0] yid_chain [`NUMS_PE_ROW:0];
    assign yid_chain[0] = YID_scan_in;


    logic [`NUMS_PE_COL-1:0] x_bus_master_valid [`NUMS_PE_ROW-1:0];
    logic [`NUMS_PE_COL-1:0] x_bus_master_ready [`NUMS_PE_ROW-1:0];
    
    logic [`NUMS_PE_ROW-1:0] x_bus_slave_valid;
    logic [`NUMS_PE_ROW-1:0] x_bus_slave_ready;
    logic [`DATA_BITS-1:0]   x_bus_slave_data [`NUMS_PE_ROW-1:0];


    logic [`XID_BITS-1:0] xid_chain [`NUMS_PE_ROW * `NUMS_PE_COL:0];
    assign xid_chain[0] = XID_scan_in;


    GON_Bus #(
        .NUMS_MASTER(`NUMS_PE_ROW),
        .ID_SIZE(`YID_BITS)
    ) y_bus (
        .clk(clk),
        .rst(rst),
        .tag(tag_Y),
        .master_valid(y_bus_master_valid),
        .master_data(y_bus_master_data),
        .master_ready(y_bus_master_ready),
        .slave_valid(GON_valid),
        .slave_ready(GON_ready),
        .slave_data(GON_data),
        .set_id(set_YID),
        .ID_scan_in(YID_scan_in),
        .ID_scan_out()
    );

    genvar row, col;
    generate
        for (row = 0; row < `NUMS_PE_ROW; row = row + 1) begin : GEN_ROW

            assign y_bus_master_data[row * `DATA_BITS +: `DATA_BITS] = x_bus_slave_data[row];
            
            GON_MulticastController #(
                .ID_SIZE(`YID_BITS)
            ) y_mc (
                .clk(clk),
                .rst(rst),
                .set_id(set_YID),
                .id_in(yid_chain[row]),
                .id(yid_chain[row+1]),
                .tag(tag_Y),
                .valid_in(x_bus_slave_valid[row]),
                .valid_out(y_bus_master_valid[row]),
                .ready_in(y_bus_master_ready[row]), 
                .ready_out(x_bus_slave_ready[row])
            );

            logic [`DATA_BITS*`NUMS_PE_COL-1:0] x_bus_master_data;

            GON_Bus #(
                .NUMS_MASTER(`NUMS_PE_COL),
                .ID_SIZE(`XID_BITS)
            ) x_bus (
                .clk(clk),
                .rst(rst),
                .tag(tag_X),
                .master_valid(x_bus_master_valid[row]),
                .master_data(x_bus_master_data),
                .master_ready(x_bus_master_ready[row]),
                .slave_valid(x_bus_slave_valid[row]),
                .slave_ready(x_bus_slave_ready[row]),
                .slave_data(x_bus_slave_data[row]),  
                .set_id(set_XID),
                .ID_scan_in(XID_scan_in), 
                .ID_scan_out() 
            );

            for (col = 0; col < `NUMS_PE_COL; col = col + 1) begin : GEN_COL
                localparam idx = row * `NUMS_PE_COL + col;

                GON_MulticastController #(
                    .ID_SIZE(`XID_BITS)
                ) x_mc (
                    .clk(clk),
                    .rst(rst),
                    .set_id(set_XID),
                    .id_in(xid_chain[idx]),
                    .id(xid_chain[idx+1]),
                    .tag(tag_X),
                    .valid_in(PE_valid[idx]),
                    .valid_out(x_bus_master_valid[row][col]),
                    .ready_in(x_bus_master_ready[row][col]), 
                    .ready_out(PE_ready[idx]) 
                );

                assign x_bus_master_data[col*`DATA_BITS +: `DATA_BITS] = PE_data[idx*`DATA_BITS +: `DATA_BITS];
            end
        end
    endgenerate

/* TODO: End of implementation */
endmodule
