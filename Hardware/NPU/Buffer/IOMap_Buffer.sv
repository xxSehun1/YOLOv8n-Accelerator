`include "define.svh"


module IOMap_Buffer #(
    parameter DEPTH = (64*1024) / (`DATA_BITS/8)
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         mode_write,             // 0 = INPUT_READ, 1 = OUTPUT_WRITE
    input  logic         start,
    input  logic [`SRAM_ADDR_BITS-1:0] base_addr,
    input  logic [31:0]  length,                 // bytes
    output logic         done,

    // SRAM port (read in INPUT mode, write in OUTPUT mode).
    output logic         sram_en,
    output logic         sram_we,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    output logic [`DATA_BITS-1:0]      sram_wdata,
    input  logic [`DATA_BITS-1:0]      sram_rdata,

    // Stream towards Line Buffer / PE (INPUT mode).
    output logic [`DATA_BITS-1:0] ifmap_data,
    output logic         ifmap_valid,
    input  logic         ifmap_ready,

    // Result stream from OpsumCollector (OUTPUT mode).
    input  logic [`DATA_BITS-1:0] ppu_data,
    input  logic         ppu_valid,
    output logic         ppu_ready
);
    typedef enum logic [2:0] {
        S_IDLE, S_RD_ISSUE, S_RD_LATCH, S_RD_OUT, S_WR, S_DONE
    } state_t;
    state_t state, next;

    logic [31:0] words_total;
    logic [31:0] word_idx;
    logic [`SRAM_ADDR_BITS-1:0] cur_addr;
    logic [`DATA_BITS-1:0]      rd_reg;

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_IDLE:     if (start) next = mode_write ? S_WR : S_RD_ISSUE;
            S_RD_ISSUE:            next = S_RD_LATCH;
            S_RD_LATCH:            next = S_RD_OUT;
            S_RD_OUT:   if (ifmap_ready) begin
                            if (word_idx == words_total - 1) next = S_DONE;
                            else                             next = S_RD_ISSUE;
                        end
            S_WR:       if (ppu_valid && word_idx == words_total - 1) next = S_DONE;
            S_DONE:                next = S_IDLE;
            default:               next = S_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            word_idx    <= '0;
            words_total <= '0;
            cur_addr    <= '0;
            rd_reg      <= '0;
        end else begin
            state <= next;
            case (state)
                S_IDLE: if (start) begin
                    word_idx    <= '0;
                    words_total <= length >> 2;
                    cur_addr    <= base_addr;
                end

                S_RD_LATCH: rd_reg <= sram_rdata;     // 1-cycle SRAM latency

                S_RD_OUT: if (ifmap_ready) begin
                    word_idx <= word_idx + 1'b1;
                    cur_addr <= cur_addr + 'd4;
                end

                S_WR: if (ppu_valid) begin
                    word_idx <= word_idx + 1'b1;
                    cur_addr <= cur_addr + 'd4;
                end

                default: ;
            endcase
        end
    end

    // Combinational outputs.
    always_comb begin
        sram_en    = 1'b0;
        sram_we    = 1'b0;
        sram_addr  = cur_addr;
        sram_wdata = '0;
        case (state)
            S_RD_ISSUE: begin
                sram_en = 1'b1;
            end
            S_WR: if (ppu_valid) begin
                sram_en    = 1'b1;
                sram_we    = 1'b1;
                sram_wdata = ppu_data;
            end
            default: ;
        endcase
    end

    assign ifmap_data  = rd_reg;
    assign ifmap_valid = (state == S_RD_OUT);
    assign ppu_ready   = (state == S_WR);
    assign done        = (state == S_DONE);

endmodule
