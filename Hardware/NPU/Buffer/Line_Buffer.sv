`include "define.svh"


module Line_Buffer #(
    parameter MAX_WIDTH = 640,
    parameter K_MAX     = 3            // physical depth (1x1 conv runs as 3x3)
)(
    input  logic         clk,
    input  logic         rst,

    // Control from the Ping-Pong Controller.
    input  logic         layer_start,            // pulse: start a new layer
    input  logic [15:0]  in_h,                   // input feature-map height
    input  logic [15:0]  in_w,                   // input feature-map width (row width)
    input  logic [15:0]  out_h,                  // output feature-map height
    input  logic [3:0]   kernel,                 // K (1 or 3, effective)
    input  logic [3:0]   stride,                 // U (vertical handled here)
    input  logic [3:0]   pad,                    // P (symmetric)
    output logic         done,                   // pulse when layer's emit finishes

    // Input stream from IOMap_Buffer.
    input  logic [`DATA_BITS-1:0] ifmap_data,
    input  logic         ifmap_valid,
    output logic         ifmap_ready,

    // Windowed output to the PE array.
    output logic [`DATA_BITS-1:0] win_data,
    output logic         win_valid,
    input  logic         win_ready
);
    // K banks of MAX_WIDTH 32-bit words plus per-bank metadata (which input
    // row this bank holds, and whether it is a halo zero row).
    logic [`DATA_BITS-1:0] mem [K_MAX-1:0][MAX_WIDTH-1:0];
    logic        bank_zero    [K_MAX-1:0];
    logic signed [15:0] bank_row_idx [K_MAX-1:0];

    // Write side (filling banks from the ifmap stream).
    logic [$clog2(K_MAX)-1:0] wr_bank;
    logic [15:0]               wr_col;
    logic signed [15:0]        next_input_row;

    // Read side (emitting the window).
    logic [$clog2(K_MAX)-1:0]  base_bank;    // oldest bank in current window
    logic [$clog2(K_MAX+1)-1:0] tap;         // 0 .. K-1 (which tap row being emitted)
    logic [15:0]               rd_col;       // 0 .. in_w-1
    logic [15:0]               oy;           // current output row
    logic [$clog2(K_MAX+1)-1:0] shift_left;  // banks left to refill in SHIFT

    typedef enum logic [2:0] {
        S_IDLE, S_WARM_UP, S_EMIT, S_SHIFT, S_DONE
    } state_t;
    state_t state, next;

    // Convenience: the input row index a given tap of the current window needs.
    function automatic logic signed [15:0] needed_row(input logic [3:0] tap_i);
        return $signed({1'b0, oy}) * $signed({12'b0, stride})
             - $signed({12'b0, pad})
             + $signed({12'b0, tap_i});
    endfunction

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_IDLE:    if (layer_start)                       next = S_WARM_UP;
            S_WARM_UP: if (wr_bank == kernel - 1 && (bank_zero[wr_bank] || wr_col == in_w - 1))
                                                              next = S_EMIT;
            S_EMIT:    if (tap == kernel - 1 && win_ready
                           && rd_col == in_w - 1) begin
                           next = (oy == out_h - 1) ? S_DONE : S_SHIFT;
                       end
            S_SHIFT:   if (shift_left == 0)                   next = S_EMIT;
            S_DONE:                                           next = S_IDLE;
            default:                                          next = S_IDLE;
        endcase
    end

    // Sequential state machine.
    int b;
    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            wr_bank       <= '0; wr_col <= '0;
            base_bank     <= '0; tap <= '0; rd_col <= '0;
            oy            <= '0; shift_left <= '0;
            next_input_row <= '0;
            for (b = 0; b < K_MAX; b++) begin
                bank_zero[b]    <= 1'b0;
                bank_row_idx[b] <= '0;
            end
        end else begin
            state <= next;

            case (state)
                S_IDLE: if (layer_start) begin
                    // Set up the first window. Top-pad rows are negative
                    // input-row indices and get marked as zero halo.
                    wr_bank   <= '0; wr_col <= '0;
                    base_bank <= '0; tap    <= '0; rd_col <= '0;
                    oy        <= '0;
                    next_input_row <= -$signed({12'b0, pad});
                    for (b = 0; b < K_MAX; b++) begin
                        bank_zero[b]    <= 1'b0;
                        bank_row_idx[b] <= '0;
                    end
                end

                S_WARM_UP: begin
                    // Mark a zero (top-pad) bank without consuming the stream
                    // and step to the next bank in the same cycle.
                    if (next_input_row < 0) begin
                        bank_zero[wr_bank]    <= 1'b1;
                        bank_row_idx[wr_bank] <= next_input_row;
                        next_input_row        <= next_input_row + 16'sd1;
                        if (wr_bank != kernel - 1) wr_bank <= wr_bank + 1'b1;
                    end else if (ifmap_valid) begin
                        mem[wr_bank][wr_col]  <= ifmap_data;
                        if (wr_col == in_w - 1) begin
                            bank_zero[wr_bank]    <= 1'b0;
                            bank_row_idx[wr_bank] <= next_input_row;
                            wr_col                <= '0;
                            next_input_row        <= next_input_row + 16'sd1;
                            if (wr_bank != kernel - 1) wr_bank <= wr_bank + 1'b1;
                        end else begin
                            wr_col <= wr_col + 16'd1;
                        end
                    end
                end

                S_EMIT: if (win_ready) begin
                    if (rd_col == in_w - 1) begin
                        rd_col <= '0;
                        if (tap == kernel - 1) begin
                            // Finished all K rows for this output row.
                            tap <= '0;
                            if (oy != out_h - 1) begin
                                oy         <= oy + 16'd1;
                                shift_left <= stride;
                            end
                        end else begin
                            tap <= tap + 1'b1;
                        end
                    end else begin
                        rd_col <= rd_col + 16'd1;
                    end
                end

                S_SHIFT: begin
                    // Free one bank per cycle until U banks have been refilled
                    // (or marked as bottom-pad zero). Wait on ifmap_valid when
                    // a real row is needed.
                    if (shift_left != 0) begin
                        // The bank at base_bank is the oldest; advance base
                        // and reuse its slot for the new row.
                        if (next_input_row >= $signed({1'b0, in_h})) begin
                            bank_zero[base_bank]    <= 1'b1;
                            bank_row_idx[base_bank] <= next_input_row;
                            next_input_row          <= next_input_row + 16'sd1;
                            base_bank               <= (base_bank + 1'b1) % kernel;
                            shift_left              <= shift_left - 1'b1;
                            wr_col                  <= '0;
                        end else if (ifmap_valid) begin
                            mem[base_bank][wr_col] <= ifmap_data;
                            if (wr_col == in_w - 1) begin
                                bank_zero[base_bank]    <= 1'b0;
                                bank_row_idx[base_bank] <= next_input_row;
                                wr_col                  <= '0;
                                next_input_row          <= next_input_row + 16'sd1;
                                base_bank               <= (base_bank + 1'b1) % kernel;
                                shift_left              <= shift_left - 1'b1;
                            end else begin
                                wr_col <= wr_col + 16'd1;
                            end
                        end
                    end
                end

                default: ;
            endcase
        end
    end

    // Combinational outputs.

    // Which physical bank holds the row for the current tap.
    logic [$clog2(K_MAX)-1:0] read_bank;
    assign read_bank = (base_bank + tap) % kernel;


    logic signed [15:0] win_col;
    assign win_col = $signed({1'b0, rd_col}) - $signed({12'b0, pad});

    logic row_is_zero, col_is_zero;
    assign row_is_zero = bank_zero[read_bank];
    assign col_is_zero = (win_col < 0)
                       | (win_col >= $signed({1'b0, in_w}));

    assign win_data  = (row_is_zero | col_is_zero) ? '0
                                                   : mem[read_bank][win_col[15:0]];
    assign win_valid = (state == S_EMIT);

    // Accept ifmap words while filling a real (non-pad) bank.
    assign ifmap_ready = (state == S_WARM_UP && next_input_row >= 0)
                       | (state == S_SHIFT  && next_input_row < $signed({1'b0, in_h})
                                            && shift_left != 0);

    assign done = (state == S_DONE);

endmodule
