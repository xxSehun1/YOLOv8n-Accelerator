`include "define.svh"

module Line_Buffer #(
    parameter MAX_WIDTH = 640,
    parameter K_MAX     = 3
)(
    input  logic         clk,
    input  logic         rst,

    input  logic         layer_start,
    input  logic [15:0]  in_h,
    input  logic [15:0]  in_w,
    input  logic [15:0]  out_h,
    input  logic [3:0]   kernel,
    input  logic [3:0]   stride,
    input  logic [3:0]   pad,
    output logic         done,

    input  logic [`DATA_BITS-1:0] ifmap_data,
    input  logic         ifmap_valid,
    output logic         ifmap_ready,

    input  logic         spatial_mode,
    input  logic [15:0]  spatial_cols,
    output logic [`NUMS_PE_COL*`DATA_BITS-1:0] win_vec_data,
    output logic         win_vec_valid,
    input  logic         win_vec_ready,

    output logic [`DATA_BITS-1:0] win_data,
    output logic         win_valid,
    input  logic         win_ready
);
    logic [`DATA_BITS-1:0] mem [K_MAX-1:0][MAX_WIDTH-1:0];
    logic        bank_zero    [K_MAX-1:0];
    logic signed [15:0] bank_row_idx [K_MAX-1:0];

    logic [$clog2(K_MAX)-1:0]  wr_bank;
    logic [15:0]               wr_col;
    logic signed [15:0]        next_input_row;

    logic [$clog2(K_MAX)-1:0]  base_bank;
    logic [$clog2(K_MAX+1)-1:0] tap_y;
    logic [$clog2(K_MAX+1)-1:0] tap_x;
    logic [15:0]               ow;
    logic [15:0]               oy;
    logic [$clog2(K_MAX+1)-1:0] shift_left;

    logic [15:0] stride_eff;
    logic [3:0]  kernel_eff;
    logic [15:0] out_w_calc;

    typedef enum logic [2:0] {
        S_IDLE, S_WARM_UP, S_EMIT, S_SHIFT, S_DONE
    } state_t;
    state_t state, next;

    function automatic logic [15:0] calc_out_dim(
        input logic [15:0] in_dim,
        input logic [3:0]  pad_v,
        input logic [3:0]  kernel_v,
        input logic [15:0] stride_v
    );
        logic [31:0] padded;
        logic [31:0] k32;
        logic [31:0] s32;
        begin
            padded = {16'd0, in_dim} + ({28'd0, pad_v} << 1);
            k32 = {28'd0, kernel_v};
            s32 = {16'd0, stride_v};
            if (padded < k32) calc_out_dim = 16'd0;
            else              calc_out_dim = 16'(((padded - k32) / s32) + 32'd1);
        end
    endfunction

    assign stride_eff = (stride == 4'd0) ? 16'd1 : {12'd0, stride};
    assign kernel_eff = (kernel == 4'd0) ? 4'd1  : kernel;
    assign out_w_calc = calc_out_dim(in_w, pad, kernel_eff, stride_eff);

    always_comb begin
        next = state;
        case (state)
            S_IDLE: if (layer_start) next = S_WARM_UP;
            S_WARM_UP: begin
                if (wr_bank == kernel_eff - 1
                    && (bank_zero[wr_bank] || (ifmap_valid && wr_col == in_w - 1)))
                    next = S_EMIT;
            end
            S_EMIT: begin
                if (!spatial_mode) begin
                    if (win_ready && ow == out_w_calc - 1
                        && tap_y == kernel_eff - 1 && tap_x == kernel_eff - 1) begin
                        next = (oy == out_h - 1) ? S_DONE : S_SHIFT;
                    end
                end else begin
                    if (win_vec_ready && (ow + spatial_cols >= out_w_calc)
                        && tap_y == kernel_eff - 1 && tap_x == kernel_eff - 1) begin
                        next = (oy == out_h - 1) ? S_DONE : S_SHIFT;
                    end
                end
            end
            S_SHIFT: if (shift_left == 0) next = S_EMIT;
            S_DONE: next = S_IDLE;
            default: next = S_IDLE;
        endcase
    end

    int b;
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            wr_bank <= '0;
            wr_col <= '0;
            next_input_row <= '0;
            base_bank <= '0;
            tap_y <= '0;
            tap_x <= '0;
            ow <= '0;
            oy <= '0;
            shift_left <= '0;
            for (b = 0; b < K_MAX; b++) begin
                bank_zero[b] <= 1'b0;
                bank_row_idx[b] <= '0;
            end
        end else begin
            state <= next;

            case (state)
                S_IDLE: if (layer_start) begin
                    wr_bank <= '0;
                    wr_col <= '0;
                    base_bank <= '0;
                    tap_y <= '0;
                    tap_x <= '0;
                    ow <= '0;
                    oy <= '0;
                    shift_left <= '0;
                    next_input_row <= -$signed({12'b0, pad});
                    for (b = 0; b < K_MAX; b++) begin
                        bank_zero[b] <= 1'b0;
                        bank_row_idx[b] <= '0;
                    end
                end

                S_WARM_UP: begin
                    if (next_input_row < 0) begin
                        bank_zero[wr_bank] <= 1'b1;
                        bank_row_idx[wr_bank] <= next_input_row;
                        next_input_row <= next_input_row + 16'sd1;
                        if (wr_bank != kernel_eff - 1) wr_bank <= wr_bank + 1'b1;
                    end else if (ifmap_valid) begin
                        mem[wr_bank][wr_col] <= ifmap_data;
                        if (wr_col == in_w - 1) begin
                            bank_zero[wr_bank] <= 1'b0;
                            bank_row_idx[wr_bank] <= next_input_row;
                            wr_col <= '0;
                            next_input_row <= next_input_row + 16'sd1;
                            if (wr_bank != kernel_eff - 1) wr_bank <= wr_bank + 1'b1;
                        end else begin
                            wr_col <= wr_col + 16'd1;
                        end
                    end
                end

                S_EMIT: if ((!spatial_mode && win_ready) || (spatial_mode && win_vec_ready)) begin
                    if (tap_x == kernel_eff - 1) begin
                        tap_x <= '0;
                        if (tap_y == kernel_eff - 1) begin
                            tap_y <= '0;
                            if (!spatial_mode) begin
                                if (ow == out_w_calc - 1) begin
                                    ow <= '0;
                                    if (oy != out_h - 1) begin
                                        oy <= oy + 16'd1;
                                        shift_left <= stride_eff[$clog2(K_MAX+1)-1:0];
                                    end
                                end else begin
                                    ow <= ow + 16'd1;
                                end
                            end else begin
                                if (ow + spatial_cols >= out_w_calc) begin
                                    ow <= '0;
                                    if (oy != out_h - 1) begin
                                        oy <= oy + 16'd1;
                                        shift_left <= stride_eff[$clog2(K_MAX+1)-1:0];
                                    end
                                end else begin
                                    ow <= ow + spatial_cols;
                                end
                            end
                        end else begin
                            tap_y <= tap_y + 1'b1;
                        end
                    end else begin
                        tap_x <= tap_x + 1'b1;
                    end
                end

                S_SHIFT: begin
                    if (shift_left != 0) begin
                        if (next_input_row >= $signed({1'b0, in_h})) begin
                            bank_zero[base_bank] <= 1'b1;
                            bank_row_idx[base_bank] <= next_input_row;
                            next_input_row <= next_input_row + 16'sd1;
                            base_bank <= (base_bank + 1'b1) % kernel_eff;
                            shift_left <= shift_left - 1'b1;
                            wr_col <= '0;
                        end else if (ifmap_valid) begin
                            mem[base_bank][wr_col] <= ifmap_data;
                            if (wr_col == in_w - 1) begin
                                bank_zero[base_bank] <= 1'b0;
                                bank_row_idx[base_bank] <= next_input_row;
                                wr_col <= '0;
                                next_input_row <= next_input_row + 16'sd1;
                                base_bank <= (base_bank + 1'b1) % kernel_eff;
                                shift_left <= shift_left - 1'b1;
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

    logic [$clog2(K_MAX)-1:0] read_bank;
    logic signed [31:0] win_col;
    logic row_is_zero;
    logic col_is_zero;

    assign read_bank = (base_bank + tap_y) % kernel_eff;
    assign win_col = ($signed({1'b0, ow}) * $signed({16'd0, stride_eff}))
                   + $signed({28'd0, tap_x})
                   - $signed({28'd0, pad});
    assign row_is_zero = bank_zero[read_bank];
    assign col_is_zero = (win_col < 0) || (win_col >= $signed({16'd0, in_w}));

    assign win_data = (row_is_zero || col_is_zero) ? 32'h8080_8080 : mem[read_bank][win_col[15:0]];
    assign win_valid = (state == S_EMIT) && !spatial_mode;
    assign win_vec_valid = (state == S_EMIT) && spatial_mode;

    always_comb begin
        win_vec_data = '0;
        for (int c = 0; c < `NUMS_PE_COL; c++) begin
            logic [15:0] out_col;
            logic signed [31:0] vec_col;
            logic vec_col_zero;

            out_col = ow + c[15:0];
            vec_col = ($signed({1'b0, out_col}) * $signed({16'd0, stride_eff}))
                    + $signed({28'd0, tap_x})
                    - $signed({28'd0, pad});
            vec_col_zero = (c >= spatial_cols) || (out_col >= out_w_calc)
                         || (vec_col < 0) || (vec_col >= $signed({16'd0, in_w}));

            if (row_is_zero || vec_col_zero) begin
                win_vec_data[c*`DATA_BITS +: `DATA_BITS] = 32'h8080_8080;
            end else begin
                win_vec_data[c*`DATA_BITS +: `DATA_BITS] = mem[read_bank][vec_col[15:0]];
            end
        end
    end

    assign ifmap_ready = (state == S_WARM_UP && next_input_row >= 0)
                       || (state == S_SHIFT && next_input_row < $signed({1'b0, in_h})
                                           && shift_left != 0);

    assign done = (state == S_DONE);
endmodule
