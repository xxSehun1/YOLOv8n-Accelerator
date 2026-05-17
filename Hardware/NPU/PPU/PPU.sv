`include "PostQuant.sv"
`include "Maxpool_Qint8.sv"
`include "SiLU_Qint8.sv"
`include "define.svh"
// PPU: post-processing unit (one lane).
//
// Pipeline: PSUM(int32) -> PostQuant(>>shift -> int8) -> SiLU activation
// (int8, LUT) -> Maxpool (POOL op only) -> +128 zero point -> uint8.
//
// Bias is not handled here: the INT32 bias is folded into the accumulator seed
// inside PSUM_acc, so PPU receives an already-biased psum. The YOLOv8n
// backbone uses SiLU everywhere; the lab ReLU stage is dropped.
module PPU (
    input  logic                   clk,
    input  logic                   rst,
    input  logic [`DATA_BITS-1:0]   data_in,        // biased psum (int32)
    input  logic [5:0]              shift,          // requant right shift
    input  logic                    silu_en,        // FLAGS bit0 & bit1
    input  logic                    maxpool_en,     // POOL instruction
    input  logic                    maxpool_init,   // first elem of a pool window
    output logic [7:0]              data_out        // uint8 (zero point added)
);
    logic [7:0]        result_PTQ;
    logic signed [7:0] result_SiLU;
    logic [7:0]        result_MaxPool;
    logic [7:0]        out;

    PostQuant PTQ (
        .data_in(data_in),
        .scaling_factor(shift),
        .data_out(result_PTQ)
    );

    SiLU_Qint8 SiLU (
        .en(silu_en),
        .data_in(result_PTQ),
        .data_out(result_SiLU)
    );

    Maxpool_Qint8 MaxPool (
        .clk(clk),
        .rst(rst),
        .en(maxpool_en),
        .init(maxpool_init),
        .data_in(result_SiLU),
        .data_out(result_MaxPool)
    );

    always_comb begin
        if (maxpool_en) out = result_MaxPool;
        else            out = result_SiLU;
    end

    assign data_out = out + 8'd128;
endmodule
