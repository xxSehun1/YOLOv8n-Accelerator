`include "GIN_Bus.sv"
`include "GIN_MulticastController.sv"

module GIN (
    input clk,
    input rst,

    // Slave SRAM <-> GIN
    input GIN_valid,
    output logic GIN_ready,
    input [`DATA_BITS - 1:0] GIN_data,

    /* Controller <-> GIN */
    input [`XID_BITS - 1:0] tag_X,
    input [`YID_BITS - 1:0] tag_Y,

    /* config */
    input set_XID,
    input [`XID_BITS - 1:0] XID_scan_in,
    input set_YID,
    input [`YID_BITS - 1:0] YID_scan_in,

    // Master GIN <-> PE
    input [`NUMS_PE_ROW * `NUMS_PE_COL - 1:0] PE_ready,
    output logic [`NUMS_PE_ROW * `NUMS_PE_COL - 1:0] PE_valid,
    output logic [`DATA_BITS - 1:0] PE_data
);
/* TODO: Start writing your implementation here */

    logic [`NUMS_PE_ROW-1:0] y_bus_valid;
    logic [`NUMS_PE_ROW-1:0] y_bus_ready;
    logic [`DATA_BITS-1:0]   y_bus_data;

    logic [`NUMS_PE_ROW-1:0] y_mc_valid;
    logic [`NUMS_PE_ROW-1:0] y_mc_ready;


    logic [`YID_BITS-1:0] yid_chain [`NUMS_PE_ROW:0];
    assign yid_chain[0] = YID_scan_in;


    logic [`NUMS_PE_COL-1:0] x_bus_valid [`NUMS_PE_ROW-1:0];
    logic [`NUMS_PE_COL-1:0] x_bus_ready [`NUMS_PE_ROW-1:0];
    logic [`DATA_BITS-1:0]   x_bus_data  [`NUMS_PE_ROW-1:0];


    logic [`XID_BITS-1:0] xid_chain [`NUMS_PE_ROW * `NUMS_PE_COL:0];
    assign xid_chain[0] = XID_scan_in;



    assign PE_data = GIN_data;



    GIN_Bus #(
        .NUMS_SLAVE(`NUMS_PE_ROW),
        .ID_SIZE(`YID_BITS)
    ) y_bus (
        .clk(clk),
        .rst(rst),
        .tag(tag_Y),
        .master_valid(GIN_valid),
        .master_data(GIN_data),
        .master_ready(GIN_ready),
        .slave_ready(y_bus_ready),
        .slave_valid(y_bus_valid),
        .slave_data(y_bus_data),
        .set_id(set_YID),
        .ID_scan_in(YID_scan_in),
        .ID_scan_out()
    );

    genvar row, col;
    generate
        for (row = 0; row < `NUMS_PE_ROW; row = row + 1) begin : GEN_ROW
            

            GIN_MulticastController #(
                .ID_SIZE(`YID_BITS)
            ) y_mc (
                .clk(clk),
                .rst(rst),
                .set_id(set_YID),
                .id_in(yid_chain[row]),
                .id(yid_chain[row+1]),
                .tag(tag_Y),
                .valid_in(y_bus_valid[row]),
                .valid_out(y_mc_valid[row]),
                .ready_in(y_mc_ready[row]),
                .ready_out(y_bus_ready[row])
            );

            GIN_Bus #(
                .NUMS_SLAVE(`NUMS_PE_COL),
                .ID_SIZE(`XID_BITS)
            ) x_bus (
                .clk(clk),
                .rst(rst),
                .tag(tag_X),
                .master_valid(y_mc_valid[row]), 
                .master_data(y_bus_data),
                .master_ready(y_mc_ready[row]),
                .slave_ready(x_bus_ready[row]),
                .slave_valid(x_bus_valid[row]),
                .slave_data(x_bus_data[row]),
                .set_id(set_XID),
                .ID_scan_in(XID_scan_in),
                .ID_scan_out() 
            );

            for (col = 0; col < `NUMS_PE_COL; col = col + 1) begin : GEN_COL
                localparam idx = row * `NUMS_PE_COL + col;


                GIN_MulticastController #(
                    .ID_SIZE(`XID_BITS)
                ) x_mc (
                    .clk(clk),
                    .rst(rst),
                    .set_id(set_XID),
                    .id_in(xid_chain[idx]),
                    .id(xid_chain[idx+1]),
                    .tag(tag_X),
                    .valid_in(x_bus_valid[row][col]),
                    .valid_out(PE_valid[idx]),
                    .ready_in(PE_ready[idx]),
                    .ready_out(x_bus_ready[row][col])
                );
            end
        end
    endgenerate

/* TODO: End of implementation */
endmodule
