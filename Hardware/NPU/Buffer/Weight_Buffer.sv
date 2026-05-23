`include "define.svh"
// Weight_Buffer: 64 KiB ping-pong weight buffer (instantiate x2).
//
// FSM: EMPTY -> FILLING -> FULL -> READING. Prefetches the next layer's
// weights from SRAM while the current layer computes; then streams filter
// words to the PE array (via the GIN) with a valid/ready handshake.


module Weight_Buffer #(
    parameter DEPTH = (64*1024) / (`DATA_BITS/8)     // 64 KiB / 4 B = 16384
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         fill_start,
    input  logic [`SRAM_ADDR_BITS-1:0] fill_addr,
    input  logic [31:0]  fill_bytes,
    output logic         fill_done,

    // SRAM read port (to fill).
    output logic         sram_en,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    input  logic [`DATA_BITS-1:0]      sram_rdata,

    // PE-array filter feed.
    output logic [`DATA_BITS-1:0] filter_data,
    output logic         filter_valid,
    input  logic         filter_ready
);
    localparam AW = $clog2(DEPTH);

    typedef enum logic [1:0] {
        S_EMPTY, S_FILLING, S_FULL, S_READING
    } state_t;
    state_t state, next;

    logic [`DATA_BITS-1:0] mem [0:DEPTH-1];

    logic [AW-1:0]  wr_idx, rd_idx;           // write / read pointers
    logic [AW:0]    wr_total;                 // total words to fill (= fill_bytes >> 2)
    logic [AW:0]    issued, latched;          // words issued / written so far
    logic [`SRAM_ADDR_BITS-1:0] cur_sram_addr;

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_EMPTY:   if (fill_start)              next = S_FILLING;
            S_FILLING: if (latched == wr_total)     next = S_FULL;
            S_FULL:                                  next = S_READING;
            S_READING: if (rd_idx == wr_total - 1 && filter_ready) next = S_EMPTY;
            default:                                 next = S_EMPTY;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state    <= S_EMPTY;
            wr_idx   <= '0; rd_idx <= '0;
            wr_total <= '0; issued <= '0; latched <= '0;
            cur_sram_addr <= '0;
        end else begin
            state <= next;
            case (state)
                S_EMPTY: if (fill_start) begin
                    wr_idx       <= '0;
                    rd_idx       <= '0;
                    issued       <= '0;
                    latched      <= '0;
                    wr_total     <= fill_bytes[AW+2:2];   // bytes / 4
                    cur_sram_addr <= fill_addr;
                end

                S_FILLING: begin
                    // Issue a new read each cycle while there are words left,
                    // and latch the previous cycle's rdata.
                    if (issued > 0) begin
                        mem[wr_idx] <= sram_rdata;
                        wr_idx      <= wr_idx + 1'b1;
                        latched     <= latched + 1'b1;
                    end
                    if (issued < wr_total) begin
                        cur_sram_addr <= cur_sram_addr + 'd4;
                        issued        <= issued + 1'b1;
                    end
                end

                S_FULL: rd_idx <= '0;

                S_READING: if (filter_ready) begin
                    rd_idx <= rd_idx + 1'b1;
                end

                default: ;
            endcase
        end
    end

    // Combinational outputs.
    assign sram_en   = (state == S_FILLING) && (issued < wr_total);
    assign sram_addr = cur_sram_addr;

    assign filter_data  = mem[rd_idx];
    assign filter_valid = (state == S_READING);

    // fill_done is held high once the buffer is at least FULL so the
    // controller can pipeline the next op.
    assign fill_done = (state == S_FULL) || (state == S_READING);

endmodule
