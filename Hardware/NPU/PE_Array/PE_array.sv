`include "PE.sv"
`include "GIN.sv"
`include "GON.sv"

module PE_array #(
    parameter NUMS_PE_ROW = `NUMS_PE_ROW,
    parameter NUMS_PE_COL = `NUMS_PE_COL,
    parameter XID_BITS = `XID_BITS,
    parameter YID_BITS = `YID_BITS,
    parameter DATA_SIZE = `DATA_BITS,
    parameter CONFIG_SIZE = `CONFIG_SIZE
)(
    input clk,
    input rst,

    /* Scan Chain */
    input set_XID,
    input [`XID_BITS-1:0] ifmap_XID_scan_in,
    input [`XID_BITS-1:0] filter_XID_scan_in,
    input [`XID_BITS-1:0] ipsum_XID_scan_in,
    input [`XID_BITS-1:0] opsum_XID_scan_in,
    // output [XID_BITS-1:0] XID_scan_out,

    input set_YID,
    input [`YID_BITS-1:0] ifmap_YID_scan_in,
    input [`YID_BITS-1:0] filter_YID_scan_in,
    input [`YID_BITS-1:0] ipsum_YID_scan_in,
    input [`YID_BITS-1:0] opsum_YID_scan_in,
    // output logic [YID_BITS-1:0] YID_scan_out,

    input set_LN,
    input [`NUMS_PE_ROW-2:0] LN_config_in,

    /* Controller */
    input [`NUMS_PE_ROW*`NUMS_PE_COL-1:0] PE_en,
    input [`CONFIG_SIZE-1:0] PE_config,
    input [`XID_BITS-1:0] ifmap_tag_X,
    input [`YID_BITS-1:0] ifmap_tag_Y,
    input [`XID_BITS-1:0] filter_tag_X,
    input [`YID_BITS-1:0] filter_tag_Y,
    input [`XID_BITS-1:0] ipsum_tag_X,
    input [`YID_BITS-1:0] ipsum_tag_Y,
    input [`XID_BITS-1:0] opsum_tag_X,
    input [`YID_BITS-1:0] opsum_tag_Y,

    /* GLB */
    input GLB_ifmap_valid,
    output logic GLB_ifmap_ready,
    input GLB_filter_valid,
    output logic GLB_filter_ready,
    input GLB_ipsum_valid,
    output logic GLB_ipsum_ready,
    input [DATA_SIZE-1:0] GLB_data_in,

    output logic GLB_opsum_valid,
    input GLB_opsum_ready,
    output logic [DATA_SIZE-1:0] GLB_data_out

);
/* TODO: Start writing your implementation here */

localparam NUM_PE = NUMS_PE_ROW * NUMS_PE_COL;


    // Ifmap GIN Signal
    logic [NUM_PE-1:0] ifmap_valid, ifmap_ready;
    logic [DATA_SIZE-1:0] ifmap_data;

    // Filter GIN Signal
    logic [NUM_PE-1:0] filter_valid, filter_ready;
    logic [DATA_SIZE-1:0] filter_data;

    // Ipsum GIN Signal
    logic [NUM_PE-1:0] gin_ipsum_valid, gin_ipsum_ready;
    logic [DATA_SIZE-1:0] gin_ipsum_data;

    // Opsum GON Signal
    logic [NUM_PE-1:0] gon_opsum_valid, gon_opsum_ready;
    logic [NUM_PE*DATA_SIZE-1:0] pe_opsum_data_flat;


    logic [NUM_PE-1:0]    pe_ipsum_valid_in;
    logic [NUM_PE-1:0]    pe_ipsum_ready_out;
    logic [DATA_SIZE-1:0] pe_ipsum_data_in [0:NUM_PE-1];

    logic [NUM_PE-1:0]    pe_opsum_valid_out;
    logic [NUM_PE-1:0]    pe_opsum_ready_in;
    logic [DATA_SIZE-1:0] pe_opsum_data_out [0:NUM_PE-1];


    GIN ifmap_GIN (
        .clk(clk), 
        .rst(rst),
        .GIN_valid(GLB_ifmap_valid), 
        .GIN_ready(GLB_ifmap_ready), 
        .GIN_data(GLB_data_in),
        .tag_X(ifmap_tag_X), 
        .tag_Y(ifmap_tag_Y),
        .set_XID(set_XID), 
        .XID_scan_in(ifmap_XID_scan_in),
        .set_YID(set_YID), 
        .YID_scan_in(ifmap_YID_scan_in),
        .PE_ready(ifmap_ready), 
        .PE_valid(ifmap_valid), 
        .PE_data(ifmap_data)
    );

    GIN filter_GIN (
        .clk(clk), 
        .rst(rst),
        .GIN_valid(GLB_filter_valid), 
        .GIN_ready(GLB_filter_ready), 
        .GIN_data(GLB_data_in),
        .tag_X(filter_tag_X), 
        .tag_Y(filter_tag_Y),
        .set_XID(set_XID), 
        .XID_scan_in(filter_XID_scan_in),
        .set_YID(set_YID), 
        .YID_scan_in(filter_YID_scan_in),
        .PE_ready(filter_ready), 
        .PE_valid(filter_valid), 
        .PE_data(filter_data)
    );

    GIN ipsum_GIN (
        .clk(clk),
        .rst(rst),
        .GIN_valid(GLB_ipsum_valid),
        .GIN_ready(GLB_ipsum_ready),
        .GIN_data(GLB_data_in),
        .tag_X(ipsum_tag_X),
        .tag_Y(ipsum_tag_Y),
        .set_XID(set_XID),
        .XID_scan_in(ipsum_XID_scan_in),
        .set_YID(set_YID),
        .YID_scan_in(ipsum_YID_scan_in),
        .PE_ready(gin_ipsum_ready),
        .PE_valid(gin_ipsum_valid),
        .PE_data(gin_ipsum_data)
    );

 
    GON opsum_GON (
        .clk(clk),
        .rst(rst),
        .GON_valid(GLB_opsum_valid),
        .GON_ready(GLB_opsum_ready),
        .GON_data(GLB_data_out),
        .tag_X(opsum_tag_X), 
        .tag_Y(opsum_tag_Y),
        .set_XID(set_XID),
        .XID_scan_in(opsum_XID_scan_in),
        .set_YID(set_YID),
        .YID_scan_in(opsum_YID_scan_in),
        .PE_valid(gon_opsum_valid),
        .PE_ready(gon_opsum_ready),
        .PE_data(pe_opsum_data_flat)
    );


    genvar row, col;
    generate
        for (row = 0; row < NUMS_PE_ROW; row = row + 1) begin : ROW
            for (col = 0; col < NUMS_PE_COL; col = col + 1) begin : COL
                
 
                localparam idx = row * NUMS_PE_COL + col;
                localparam idx_below = (row == NUMS_PE_ROW - 1) ? idx : (row + 1) * NUMS_PE_COL + col;
                localparam idx_above = (row == 0)               ? idx : (row - 1) * NUMS_PE_COL + col;

                logic sel_LN;
                logic used_by_LN_above;

                assign pe_opsum_data_flat[idx*DATA_SIZE +: DATA_SIZE] = pe_opsum_data_out[idx];


                if (row == NUMS_PE_ROW - 1) begin
                    assign sel_LN = 1'b0;
                end else begin
                    assign sel_LN = LN_config_in[row];
                end

                if (row == 0) begin
                    assign used_by_LN_above = 1'b0;
                end else begin
                    assign used_by_LN_above = LN_config_in[row-1];
                end


                assign pe_ipsum_data_in[idx]  = sel_LN ? pe_opsum_data_out[idx_below]  : gin_ipsum_data;
                assign pe_ipsum_valid_in[idx] = sel_LN ? pe_opsum_valid_out[idx_below] : gin_ipsum_valid[idx];
                assign gin_ipsum_ready[idx]   = sel_LN ? 1'b1 : pe_ipsum_ready_out[idx];
                assign gon_opsum_valid[idx]   = used_by_LN_above ? 1'b0 : pe_opsum_valid_out[idx];
                assign pe_opsum_ready_in[idx] = used_by_LN_above ? pe_ipsum_ready_out[idx_above] : gon_opsum_ready[idx];


                PE pe_inst (

                    .clk(clk),
                    .rst(rst),
                    .PE_en(PE_en[idx]),
                    .i_config(PE_config),
                    .ifmap(ifmap_data),
                    .filter(filter_data),
                    .ipsum(pe_ipsum_data_in[idx]),
                    .ifmap_valid(ifmap_valid[idx]),
                    .filter_valid(filter_valid[idx]),
                    .ipsum_valid(pe_ipsum_valid_in[idx]),
                    .opsum_ready(pe_opsum_ready_in[idx]),
                    .opsum(pe_opsum_data_out[idx]),
                    .ifmap_ready(ifmap_ready[idx]),
                    .filter_ready(filter_ready[idx]),
                    .ipsum_ready(pe_ipsum_ready_out[idx]),
                    .opsum_valid(pe_opsum_valid_out[idx])
                );

            end
        end
    endgenerate

/* TODO: End of implementation */
endmodule