`include "define.svh"

// AddAddrGen
//
// Linear address generator for residual ADD.
// The tensor layout is C,H,W contiguous bytes. The generator uses counters and
// a byte offset accumulator; no division or modulo is used in the hot path.
module AddAddrGen (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic        next_elem,
    output logic        add_done,

    input  logic [15:0] in_h,
    input  logic [15:0] in_w,
    input  logic [15:0] in_c,
    input  logic [31:0] lhs_addr_base,
    input  logic [31:0] rhs_addr_base,
    input  logic [31:0] out_addr_base,

    output logic [31:0] lhs_addr,
    output logic [31:0] rhs_addr,
    output logic [31:0] out_addr,
    output logic        elem_done,

    output logic [15:0] dbg_c,
    output logic [15:0] dbg_h,
    output logic [15:0] dbg_w,
    output logic [31:0] dbg_byte_offset
);
    logic [15:0] c, h, w;
    logic [31:0] byte_offset;

    assign elem_done = (w == in_w - 16'd1) &&
                       (h == in_h - 16'd1) &&
                       (c == in_c - 16'd1);

    always_ff @(posedge clk) begin
        if (rst || start) begin
            c <= '0;
            h <= '0;
            w <= '0;
            byte_offset <= '0;
            add_done <= 1'b0;
        end else if (next_elem && !add_done) begin
            if (elem_done) begin
                add_done <= 1'b1;
            end else begin
                byte_offset <= byte_offset + 32'd1;
                if (w == in_w - 16'd1) begin
                    w <= '0;
                    if (h == in_h - 16'd1) begin
                        h <= '0;
                        c <= c + 16'd1;
                    end else begin
                        h <= h + 16'd1;
                    end
                end else begin
                    w <= w + 16'd1;
                end
            end
        end
    end

    assign lhs_addr = lhs_addr_base + byte_offset;
    assign rhs_addr = rhs_addr_base + byte_offset;
    assign out_addr = out_addr_base + byte_offset;

    assign dbg_c = c;
    assign dbg_h = h;
    assign dbg_w = w;
    assign dbg_byte_offset = byte_offset;
endmodule
