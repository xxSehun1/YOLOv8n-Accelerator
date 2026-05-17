`include "define.svh"
// DMA_ctrl: block data mover, driven by the Decoder.
//
// Handles three transfer kinds (all sized in bytes):
//   DMA_LD weight: DRAM weight region -> SRAM
//   DMA_LD input:  DRAM input region  -> SRAM
//   DMA_LD concat: SRAM -> SRAM            (dma_dram carries an SRAM addr)
//   DMA_ST:        SRAM -> DRAM
// Concat vs DRAM source is distinguished by dma_dram < DRAM_WEIGHT_BASE and
// the source already being an SRAM address (see compiler notes).
module DMA_ctrl (
    input  logic         clk,
    input  logic         rst,

    // From Decoder.
    input  logic         dma_valid,
    input  logic         dma_is_store,           // 0 = LD, 1 = ST
    input  logic [31:0]  dma_dram,               // DRAM addr (or SRAM src for concat)
    input  logic [31:0]  dma_sram,               // SRAM addr
    input  logic [31:0]  dma_size,               // bytes
    output logic         dma_done,

    // DRAM interface (off-chip).
    output logic         dram_en,
    output logic         dram_we,
    output logic [31:0]  dram_addr,
    output logic [`DATA_BITS-1:0] dram_wdata,
    input  logic [`DATA_BITS-1:0] dram_rdata,

    // SRAM interface (port 0).
    output logic         sram_en,
    output logic         sram_we,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    output logic [`DATA_BITS-1:0]      sram_wdata,
    input  logic [`DATA_BITS-1:0]      sram_rdata
);
    // v1 scope: handles DMA_LD (DRAM->SRAM) and DMA_ST (SRAM->DRAM). Concat
    // (SRAM->SRAM) is not yet distinguishable from a DMA_LD and is left for a
    // follow-up (needs a dedicated opcode or flag).

    typedef enum logic [1:0] {S_IDLE, S_RD, S_WR, S_DONE} state_t;
    state_t state, next;

    logic [31:0] widx;       // current word index
    logic [31:0] nwords;     // total words = size / 4

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_IDLE: if (dma_valid)            next = S_RD;
            S_RD:                             next = S_WR;
            S_WR:   next = (widx == nwords-1) ? S_DONE : S_RD;
            S_DONE:                           next = S_IDLE;
            default:                          next = S_IDLE;
        endcase
    end

    // Sequential state and counters.
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; widx <= '0; nwords <= '0;
        end else begin
            state <= next;
            case (state)
                S_IDLE: begin widx <= '0; nwords <= dma_size >> 2; end
                S_WR:   widx <= widx + 32'd1;
                default: ;
            endcase
        end
    end

    // Combinational datapath.
    //   S_RD: drive a read on the source memory (1-cycle latency).
    //   S_WR: source rdata is now valid, write it to the destination.
    always_comb begin
        dram_en = 1'b0; dram_we = 1'b0; dram_addr  = '0; dram_wdata = '0;
        sram_en = 1'b0; sram_we = 1'b0; sram_addr  = '0; sram_wdata = '0;

        if (state == S_RD) begin
            if (dma_is_store) begin                       // SRAM -> DRAM: read SRAM
                sram_en   = 1'b1;
                sram_addr = (dma_sram + (widx << 2));
            end else begin                                // DRAM -> SRAM: read DRAM
                dram_en   = 1'b1;
                dram_addr = dma_dram + (widx << 2);
            end
        end else if (state == S_WR) begin
            if (dma_is_store) begin                       // write DRAM
                dram_en    = 1'b1; dram_we = 1'b1;
                dram_addr  = dma_dram + (widx << 2);
                dram_wdata = sram_rdata;
            end else begin                                // write SRAM
                sram_en    = 1'b1; sram_we = 1'b1;
                sram_addr  = (dma_sram + (widx << 2));
                sram_wdata = dram_rdata;
            end
        end
    end

    assign dma_done = (state == S_DONE);

endmodule
