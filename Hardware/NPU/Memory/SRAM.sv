`include "define.svh"
// SRAM: 4 MiB on-chip scratchpad (activations + weight staging).
//
// Dual-port: port 0 = DMA controller, port 1 = compute core (buffers).
// Execution is blocking, so the two ports are never both active for the same
// region at the same time. 32-bit word data; addr is a byte address
// (word-aligned, low 2 bits ignored).

module SRAM #(
    parameter ADDR_BITS = `SRAM_ADDR_BITS,       // 22 -> 4 MiB
    parameter DATA_BITS = `DATA_BITS             // 32
)(
    input  logic                 clk,
    // Port 0: DMA.
    input  logic                 a_en,
    input  logic                 a_we,
    input  logic [ADDR_BITS-1:0]  a_addr,
    input  logic [DATA_BITS-1:0]  a_wdata,
    output logic [DATA_BITS-1:0]  a_rdata,
    // Port 1: compute core (Weight / IOMap buffers).
    input  logic                 b_en,
    input  logic                 b_we,
    input  logic [ADDR_BITS-1:0]  b_addr,
    input  logic [DATA_BITS-1:0]  b_wdata,
    output logic [DATA_BITS-1:0]  b_rdata
);
    // Word-addressed storage: byte addr >> 2 indexes a 32-bit word.
    localparam WORDS    = (1 << ADDR_BITS) / (DATA_BITS / 8);
    localparam WORD_LSB = $clog2(DATA_BITS / 8);          // = 2 for 32-bit

    logic [DATA_BITS-1:0] mem [0:WORDS-1];

    // Port 0.
    always @(posedge clk) begin
        if (a_en) begin
            if (a_we) mem[a_addr[ADDR_BITS-1:WORD_LSB]] <= a_wdata;
            a_rdata <= mem[a_addr[ADDR_BITS-1:WORD_LSB]];
        end
    end

    // Port 1.
    // Correctness-first ComputeTop uses deterministic one-cycle scalar steps.
    // The compute read side is asynchronous so a state can present a byte
    // address and consume the selected 32-bit word at the same clock edge.
    // Writes remain synchronous.
    always @(posedge clk) begin
        if (b_en && b_we) begin
            mem[b_addr[ADDR_BITS-1:WORD_LSB]] <= b_wdata;
        end
    end

    always_comb begin
        if (b_en) begin
            b_rdata = mem[b_addr[ADDR_BITS-1:WORD_LSB]];
        end else begin
            b_rdata = '0;
        end
    end
endmodule
