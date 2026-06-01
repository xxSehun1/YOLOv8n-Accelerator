`include "define.svh"

// ComputeTop: correctness-first sequential compute engine.
//
// This module replaces DummyExec in the control integration path. It executes
// real CONV, POOL, and ADD operations using scalar primitive units and
// hardware-friendly address generators. The implementation is intentionally
// serial and deterministic for bit-exact bring-up, not throughput sign-off.
module ComputeTop #(
    parameter int ACC_WIDTH = 64
) (
    input  logic         clk,
    input  logic         rst,

    input  logic         exec_valid,
    input  logic [1:0]   exec_op,
    input  logic [15:0]  exec_in_h,
    input  logic [15:0]  exec_in_w,
    input  logic [15:0]  exec_in_c,
    input  logic [15:0]  exec_out_c,
    input  logic [31:0]  exec_in_addr,
    input  logic [31:0]  exec_wgt_addr,
    input  logic [31:0]  exec_out_addr,
    input  logic [11:0]  exec_flags,
    input  logic [3:0]   exec_stride,
    input  logic [3:0]   exec_pad,
    input  logic [3:0]   exec_kernel,
    input  logic [9:0]   exec_pconfig,
    input  logic [5:0]   exec_shift,
    input  logic [5:0]   exec_lhs_shift,
    input  logic [5:0]   exec_rhs_shift,
    output logic         exec_done,

    output logic         sram_en,
    output logic         sram_we,
    output logic [`SRAM_ADDR_BITS-1:0] sram_addr,
    output logic [`DATA_BITS-1:0]      sram_wdata,
    input  logic [`DATA_BITS-1:0]      sram_rdata,

    input  logic         dma_sram_en,
    input  logic         dma_sram_we,
    input  logic [`SRAM_ADDR_BITS-1:0] dma_sram_addr,
    input  logic [`DATA_BITS-1:0]      dma_sram_wdata,

    output logic [15:0]  debug_exec_count,
    output logic [15:0]  debug_conv_count,
    output logic [15:0]  debug_pool_count,
    output logic [15:0]  debug_add_count
);
    localparam logic [1:0] EXEC_CONV = 2'd0;
    localparam logic [1:0] EXEC_POOL = 2'd1;
    localparam logic [1:0] EXEC_ADD  = 2'd2;

    typedef enum logic [3:0] {
        S_IDLE,
        S_ADDR_START,
        S_PIXEL_INIT,
        S_MAC,
        S_PIXEL_PACK,
        S_WORD_WRITE,
        S_ADVANCE,
        S_DONE
    } state_t;

    localparam int SRAM_WORDS = `SRAM_SIZE / (`DATA_BITS / 8);
    localparam int WORD_LSB   = $clog2(`DATA_BITS / 8);

    state_t state, next;

    logic [1:0]  exec_op_l;
    logic [15:0] in_h_l, in_w_l, in_c_l, out_c_l;
    logic [31:0] in_addr_l, wgt_addr_l, out_addr_l;
    logic [11:0] flags_l;
    logic [3:0]  stride_l, pad_l, kernel_l;
    logic [5:0]  shift_l, lhs_shift_l, rhs_shift_l;
    logic [31:0] total_weight_bytes;
    logic [31:0] total_out_bytes;
    logic [31:0] output_byte_idx;

    logic [`DATA_BITS-1:0] sram_mirror [0:SRAM_WORDS-1];

    // CONV address generation.
    logic conv_start;
    logic conv_next_mac;
    logic addr_conv_done;
    logic [31:0] addr_act;
    logic [31:0] addr_wgt;
    logic [31:0] addr_out;
    logic addr_is_pad_zero;
    logic addr_pixel_done;
    logic [15:0] addr_oc, addr_oh, addr_ow, addr_ic;
    logic [3:0]  addr_ky, addr_kx;
    logic [15:0] addr_out_h, addr_out_w;

    // POOL address generation.
    logic pool_start;
    logic pool_next_candidate;
    logic pool_done;
    logic [31:0] pool_act_addr;
    logic [31:0] pool_out_addr;
    logic pool_is_pad_zero;
    logic pool_pixel_done;
    logic [15:0] pool_dbg_c, pool_dbg_oh, pool_dbg_ow;
    logic [3:0]  pool_dbg_ky, pool_dbg_kx;
    logic [15:0] pool_dbg_out_h, pool_dbg_out_w;

    // ADD address generation.
    logic add_start;
    logic add_next_elem;
    logic add_done;
    logic [31:0] add_lhs_addr;
    logic [31:0] add_rhs_addr;
    logic [31:0] add_out_addr;
    logic add_elem_done;
    logic [15:0] add_dbg_c, add_dbg_h, add_dbg_w;
    logic [31:0] add_dbg_byte_offset;

    logic [31:0] bias_addr;
    logic signed [31:0] bias_s32;
    logic [7:0] act_u8;
    logic signed [7:0] weight_s8;
    logic signed [ACC_WIDTH-1:0] acc;
    logic signed [8:0] mac_act_s9;
    logic signed [17:0] mac_product_s18;
    logic signed [ACC_WIDTH-1:0] mac_psum_out;
    logic signed [ACC_WIDTH-1:0] shifted_q;
    logic signed [7:0] unused_shift_clip;
    logic [7:0] unused_shift_pack;
    logic signed [ACC_WIDTH-1:0] activated_q;
    logic signed [ACC_WIDTH-1:0] final_shifted;
    logic signed [7:0] final_clip;
    logic [7:0] final_u8;

    logic pool_current_valid;
    logic [7:0] pool_current_max;
    logic [7:0] pool_candidate_u8;
    logic pool_next_valid;
    logic [7:0] pool_next_max;
    logic signed [8:0] pool_current_signed;
    logic signed [8:0] pool_candidate_signed;

    logic [7:0] add_lhs_u8;
    logic [7:0] add_rhs_u8;
    logic signed [8:0] add_lhs_signed;
    logic signed [8:0] add_rhs_signed;
    logic signed [18:0] add_sum_signed;
    logic [7:0] add_out_u8;

    logic [31:0] out_word_buf;
    logic [31:0] write_word_hold;
    logic [31:0] write_addr_hold;
    logic [31:0] current_out_addr;
    logic [7:0]  current_result_u8;
    logic        current_is_final;
    logic        mac_pixel_done;

    function automatic logic [7:0] select_byte(
        input logic [31:0] word,
        input logic [1:0] lane
    );
        case (lane)
            2'd0: select_byte = word[7:0];
            2'd1: select_byte = word[15:8];
            2'd2: select_byte = word[23:16];
            default: select_byte = word[31:24];
        endcase
    endfunction

    function automatic logic [31:0] set_byte(
        input logic [31:0] word,
        input logic [1:0] lane,
        input logic [7:0] value
    );
        begin
            set_byte = word;
            case (lane)
                2'd0: set_byte[7:0] = value;
                2'd1: set_byte[15:8] = value;
                2'd2: set_byte[23:16] = value;
                default: set_byte[31:24] = value;
            endcase
        end
    endfunction

    function automatic logic [7:0] mirror_byte(input logic [31:0] byte_addr);
        mirror_byte = select_byte(
            sram_mirror[byte_addr[`SRAM_ADDR_BITS-1:WORD_LSB]],
            byte_addr[1:0]
        );
    endfunction

    function automatic logic [31:0] aligned_word_addr(input logic [31:0] byte_addr);
        aligned_word_addr = {byte_addr[31:2], 2'b00};
    endfunction

    function automatic logic [15:0] calc_out_dim(
        input logic [15:0] in_dim,
        input logic [3:0]  pad_v,
        input logic [3:0]  kernel_v,
        input logic [3:0]  stride_v
    );
        logic [31:0] stride_tmp;
        logic [31:0] padded;
        begin
            stride_tmp = (stride_v == 4'd0) ? 32'd1 : {28'd0, stride_v};
            padded = {16'd0, in_dim} + ({28'd0, pad_v} << 1);
            if (padded < {28'd0, kernel_v}) begin
                calc_out_dim = 16'd0;
            end else begin
                calc_out_dim = 16'(((padded - {28'd0, kernel_v}) / stride_tmp) + 32'd1);
            end
        end
    endfunction

    ConvAddrGen i_addr_gen (
        .clk(clk), .rst(rst),
        .start(conv_start), .next_mac(conv_next_mac),
        .conv_done(addr_conv_done),
        .in_h(in_h_l), .in_w(in_w_l), .in_c(in_c_l), .out_c(out_c_l),
        .kernel(kernel_l), .stride(stride_l), .pad(pad_l),
        .in_addr_base(in_addr_l), .wgt_addr_base(wgt_addr_l),
        .out_addr_base(out_addr_l),
        .act_addr(addr_act), .wgt_addr(addr_wgt), .out_addr(addr_out),
        .is_pad_zero(addr_is_pad_zero), .pixel_done(addr_pixel_done),
        .dbg_oc(addr_oc), .dbg_oh(addr_oh), .dbg_ow(addr_ow),
        .dbg_ic(addr_ic), .dbg_ky(addr_ky), .dbg_kx(addr_kx),
        .dbg_out_h(addr_out_h), .dbg_out_w(addr_out_w)
    );

    PoolAddrGen i_pool_addr_gen (
        .clk(clk), .rst(rst),
        .start(pool_start), .next_candidate(pool_next_candidate),
        .pool_done(pool_done),
        .in_h(in_h_l), .in_w(in_w_l), .in_c(in_c_l),
        .kernel(kernel_l), .stride(stride_l), .pad(pad_l),
        .in_addr_base(in_addr_l), .out_addr_base(out_addr_l),
        .act_addr(pool_act_addr), .out_addr(pool_out_addr),
        .is_pad_zero(pool_is_pad_zero), .pixel_done(pool_pixel_done),
        .dbg_c(pool_dbg_c), .dbg_oh(pool_dbg_oh), .dbg_ow(pool_dbg_ow),
        .dbg_ky(pool_dbg_ky), .dbg_kx(pool_dbg_kx),
        .dbg_out_h(pool_dbg_out_h), .dbg_out_w(pool_dbg_out_w)
    );

    AddAddrGen i_add_addr_gen (
        .clk(clk), .rst(rst),
        .start(add_start), .next_elem(add_next_elem),
        .add_done(add_done),
        .in_h(in_h_l), .in_w(in_w_l), .in_c(in_c_l),
        .lhs_addr_base(in_addr_l), .rhs_addr_base(wgt_addr_l),
        .out_addr_base(out_addr_l),
        .lhs_addr(add_lhs_addr), .rhs_addr(add_rhs_addr),
        .out_addr(add_out_addr), .elem_done(add_elem_done),
        .dbg_c(add_dbg_c), .dbg_h(add_dbg_h), .dbg_w(add_dbg_w),
        .dbg_byte_offset(add_dbg_byte_offset)
    );

    ConvMacUnit #(.ACC_WIDTH(ACC_WIDTH)) i_conv_mac (
        .act_u8(act_u8),
        .weight_s8(weight_s8),
        .psum_in(acc),
        .clear(1'b0),
        .add_bias(1'b0),
        .bias_s32(32'sd0),
        .act_s9(mac_act_s9),
        .product_s18(mac_product_s18),
        .psum_out(mac_psum_out)
    );

    QuantizeUnit #(.ACC_WIDTH(ACC_WIDTH)) i_shift_quant (
        .acc_in(acc),
        .shift(shift_l),
        .shifted_signed(shifted_q),
        .clipped_signed(unused_shift_clip),
        .packed_u8(unused_shift_pack)
    );

    ActivationUnit #(.ACC_WIDTH(ACC_WIDTH), .FAST_INT_SILU(1'b1)) i_activation (
        .q_in(shifted_q),
        .flags(flags_l),
        .q_out(activated_q)
    );

    QuantizeUnit #(.ACC_WIDTH(ACC_WIDTH)) i_final_quant (
        .acc_in(activated_q),
        .shift(6'd0),
        .shifted_signed(final_shifted),
        .clipped_signed(final_clip),
        .packed_u8(final_u8)
    );

    PoolCompareUnit i_pool_compare (
        .current_valid(pool_current_valid),
        .current_max_u8(pool_current_max),
        .candidate_valid(1'b1),
        .candidate_is_pad(pool_is_pad_zero),
        .candidate_u8(pool_candidate_u8),
        .max_valid(pool_next_valid),
        .max_u8(pool_next_max),
        .current_signed(pool_current_signed),
        .candidate_signed(pool_candidate_signed)
    );

    AddUnit i_add_unit (
        .lhs_u8(add_lhs_u8),
        .rhs_u8(add_rhs_u8),
        .lhs_shift(lhs_shift_l),
        .rhs_shift(rhs_shift_l),
        .lhs_signed(add_lhs_signed),
        .rhs_signed(add_rhs_signed),
        .sum_signed(add_sum_signed),
        .out_u8(add_out_u8)
    );

    assign conv_start = (state == S_ADDR_START) && (exec_op_l == EXEC_CONV);
    assign pool_start = (state == S_ADDR_START) && (exec_op_l == EXEC_POOL);
    assign add_start  = (state == S_ADDR_START) && (exec_op_l == EXEC_ADD);

    assign conv_next_mac = (exec_op_l == EXEC_CONV) &&
                           (((state == S_MAC) && !addr_pixel_done) ||
                            ((state == S_ADVANCE) && !current_is_final));
    assign pool_next_candidate = (exec_op_l == EXEC_POOL) &&
                                 (((state == S_MAC) && !pool_pixel_done) ||
                                  ((state == S_ADVANCE) && !current_is_final));
    assign add_next_elem = (exec_op_l == EXEC_ADD) &&
                           (state == S_ADVANCE) && !current_is_final;

    assign bias_addr = wgt_addr_l + total_weight_bytes + ({16'd0, addr_oc} << 2);
    assign bias_s32 = sram_mirror[bias_addr[`SRAM_ADDR_BITS-1:WORD_LSB]];
    assign act_u8 = addr_is_pad_zero ? `ACT_ZERO_POINT : mirror_byte(addr_act);
    assign weight_s8 = mirror_byte(addr_wgt);

    assign pool_candidate_u8 = pool_is_pad_zero ? 8'd0 : mirror_byte(pool_act_addr);
    assign add_lhs_u8 = mirror_byte(add_lhs_addr);
    assign add_rhs_u8 = mirror_byte(add_rhs_addr);

    assign current_is_final = (output_byte_idx == total_out_bytes - 32'd1);
    assign mac_pixel_done = (exec_op_l == EXEC_CONV) ? addr_pixel_done :
                            (exec_op_l == EXEC_POOL) ? pool_pixel_done : 1'b1;

    always_comb begin
        unique case (exec_op_l)
            EXEC_CONV: begin
                current_out_addr = addr_out;
                current_result_u8 = final_u8;
            end
            EXEC_POOL: begin
                current_out_addr = pool_out_addr;
                current_result_u8 = pool_current_max;
            end
            EXEC_ADD: begin
                current_out_addr = add_out_addr;
                current_result_u8 = add_out_u8;
            end
            default: begin
                current_out_addr = out_addr_l;
                current_result_u8 = 8'd0;
            end
        endcase
    end

    always_comb begin
        next = state;
        case (state)
            S_IDLE: begin
                if (exec_valid) begin
                    next = (exec_op <= EXEC_ADD) ? S_ADDR_START : S_DONE;
                end
            end
            S_ADDR_START: next = (exec_op_l == EXEC_ADD) ? S_PIXEL_PACK : S_PIXEL_INIT;
            S_PIXEL_INIT: next = S_MAC;
            S_MAC:        next = mac_pixel_done ? S_PIXEL_PACK : S_MAC;
            S_PIXEL_PACK: next = ((output_byte_idx[1:0] == 2'd3) || current_is_final)
                                ? S_WORD_WRITE : S_ADVANCE;
            S_WORD_WRITE: next = current_is_final ? S_DONE : S_ADVANCE;
            S_ADVANCE:    next = (exec_op_l == EXEC_ADD) ? S_PIXEL_PACK : S_PIXEL_INIT;
            S_DONE:       next = S_IDLE;
            default:      next = S_IDLE;
        endcase
    end

    always_comb begin
        sram_en = 1'b0;
        sram_we = 1'b0;
        sram_addr = '0;
        sram_wdata = '0;
        if (state == S_WORD_WRITE) begin
            sram_en = 1'b1;
            sram_we = 1'b1;
            sram_addr = write_addr_hold[`SRAM_ADDR_BITS-1:0];
            sram_wdata = write_word_hold;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            exec_op_l <= '0;
            in_h_l <= '0;
            in_w_l <= '0;
            in_c_l <= '0;
            out_c_l <= '0;
            in_addr_l <= '0;
            wgt_addr_l <= '0;
            out_addr_l <= '0;
            flags_l <= '0;
            stride_l <= '0;
            pad_l <= '0;
            kernel_l <= '0;
            shift_l <= '0;
            lhs_shift_l <= '0;
            rhs_shift_l <= '0;
            total_weight_bytes <= '0;
            total_out_bytes <= '0;
            output_byte_idx <= '0;
            acc <= '0;
            pool_current_valid <= 1'b0;
            pool_current_max <= '0;
            out_word_buf <= '0;
            write_word_hold <= '0;
            write_addr_hold <= '0;
            debug_exec_count <= '0;
            debug_conv_count <= '0;
            debug_pool_count <= '0;
            debug_add_count <= '0;
        end else begin
            state <= next;

            if (dma_sram_en && dma_sram_we) begin
                sram_mirror[dma_sram_addr[`SRAM_ADDR_BITS-1:WORD_LSB]] <= dma_sram_wdata;
            end
            if (state == S_WORD_WRITE) begin
                sram_mirror[write_addr_hold[`SRAM_ADDR_BITS-1:WORD_LSB]] <= write_word_hold;
            end

            case (state)
                S_IDLE: begin
                    if (exec_valid) begin
                        debug_exec_count <= debug_exec_count + 16'd1;
                        if (exec_op == EXEC_CONV) debug_conv_count <= debug_conv_count + 16'd1;
                        else if (exec_op == EXEC_POOL) debug_pool_count <= debug_pool_count + 16'd1;
                        else if (exec_op == EXEC_ADD) debug_add_count <= debug_add_count + 16'd1;

                        if (exec_op > EXEC_ADD) begin
                            $fatal(1, "ComputeTop unsupported exec_op=%0d", exec_op);
                        end

                        exec_op_l <= exec_op;
                        in_h_l <= exec_in_h;
                        in_w_l <= exec_in_w;
                        in_c_l <= exec_in_c;
                        out_c_l <= exec_out_c;
                        in_addr_l <= exec_in_addr;
                        wgt_addr_l <= exec_wgt_addr;
                        out_addr_l <= exec_out_addr;
                        flags_l <= exec_flags;
                        stride_l <= (exec_stride == 4'd0) ? 4'd1 : exec_stride;
                        pad_l <= exec_pad;
                        kernel_l <= exec_kernel;
                        shift_l <= exec_shift;
                        lhs_shift_l <= exec_lhs_shift;
                        rhs_shift_l <= exec_rhs_shift;
                        total_weight_bytes <= {16'd0, exec_out_c}
                                            * {16'd0, exec_in_c}
                                            * {28'd0, exec_kernel}
                                            * {28'd0, exec_kernel};
                        if (exec_op == EXEC_ADD) begin
                            total_out_bytes <= {16'd0, exec_in_c}
                                             * {16'd0, exec_in_h}
                                             * {16'd0, exec_in_w};
                        end else if (exec_op == EXEC_POOL) begin
                            total_out_bytes <= {16'd0, exec_in_c}
                                             * {16'd0, calc_out_dim(exec_in_h, exec_pad, exec_kernel, exec_stride)}
                                             * {16'd0, calc_out_dim(exec_in_w, exec_pad, exec_kernel, exec_stride)};
                        end else begin
                            total_out_bytes <= {16'd0, exec_out_c}
                                             * {16'd0, calc_out_dim(exec_in_h, exec_pad, exec_kernel, exec_stride)}
                                             * {16'd0, calc_out_dim(exec_in_w, exec_pad, exec_kernel, exec_stride)};
                        end
                        output_byte_idx <= '0;
                        acc <= '0;
                        pool_current_valid <= 1'b0;
                        pool_current_max <= '0;
                        out_word_buf <= '0;
                        write_word_hold <= '0;
                        write_addr_hold <= '0;
                    end
                end

                S_PIXEL_INIT: begin
                    if (exec_op_l == EXEC_CONV) begin
                        acc <= flags_l[`FLAG_BIAS]
                             ? {{(ACC_WIDTH-32){bias_s32[31]}}, bias_s32}
                             : '0;
                    end else if (exec_op_l == EXEC_POOL) begin
                        pool_current_valid <= 1'b0;
                        pool_current_max <= '0;
                    end
                end

                S_MAC: begin
                    if (exec_op_l == EXEC_CONV) begin
                        acc <= mac_psum_out;
                    end else if (exec_op_l == EXEC_POOL) begin
                        pool_current_valid <= pool_next_valid;
                        pool_current_max <= pool_next_max;
                    end
                end

                S_PIXEL_PACK: begin
                    logic [31:0] packed_word;
                    packed_word = set_byte(out_word_buf, output_byte_idx[1:0], current_result_u8);
                    out_word_buf <= packed_word;
                    if ((output_byte_idx[1:0] == 2'd3) || current_is_final) begin
                        write_word_hold <= packed_word;
                        write_addr_hold <= aligned_word_addr(current_out_addr);
                    end
                end

                S_WORD_WRITE: begin
                    out_word_buf <= '0;
                end

                S_ADVANCE: begin
                    output_byte_idx <= output_byte_idx + 32'd1;
                end

                default: ;
            endcase
        end
    end

    assign exec_done = (state == S_DONE);

    logic unused_inputs;
    assign unused_inputs = ^{sram_rdata, exec_pconfig,
                             addr_conv_done, addr_oh, addr_ow, addr_ic, addr_ky, addr_kx,
                             addr_out_h, addr_out_w, pool_done, pool_dbg_c,
                             pool_dbg_oh, pool_dbg_ow, pool_dbg_ky, pool_dbg_kx,
                             pool_dbg_out_h, pool_dbg_out_w, add_done, add_elem_done,
                             add_dbg_c, add_dbg_h, add_dbg_w, add_dbg_byte_offset,
                             mac_act_s9, mac_product_s18, final_shifted, final_clip,
                             unused_shift_clip, unused_shift_pack, pool_current_signed,
                             pool_candidate_signed, add_lhs_signed, add_rhs_signed,
                             add_sum_signed};
endmodule
