`include "define.svh"
// Decoder: instruction fetch and decode.
//
// Fetches 128-bit instructions from the I-cache, decodes them, and drives the
// Ping-Pong Controller (CONV/POOL/ADD) and the DMA Controller (DMA_LD/DMA_ST).
// CONFIG/ADDCFG latch state into registers consumed by the next EXEC op.
// Execution is blocking: one instruction completes before the next is fetched.
// Instruction encoding follows the define.svh field macros, kept in sync with
// the compiler's assembler.py.
//
// Interface contract:
//   I-cache:    assert instr_req with pc; the I-cache returns instr and
//               instr_valid (combinational read on pc assumed).
//   Controller: when exec_valid is high, run the op described by the exec_*
//               fields and pulse exec_done when finished.
//   DMA:        when dma_valid is high, perform the dma_* transfer and pulse
//               dma_done when finished.
module Decoder (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,            // pulse: begin executing from pc 0

    // Instruction memory.
    output logic [15:0]  pc,
    output logic         instr_req,
    input  logic [127:0] instr,
    input  logic         instr_valid,

    // Compute command to the Ping-Pong Controller.
    output logic         exec_valid,       // held high until exec_done
    output logic [1:0]   exec_op,          // 0 = CONV, 1 = POOL, 2 = ADD
    output logic [15:0]  exec_in_h,
    output logic [15:0]  exec_in_w,
    output logic [15:0]  exec_in_c,
    output logic [15:0]  exec_out_c,
    output logic [31:0]  exec_in_addr,
    output logic [31:0]  exec_wgt_addr,
    output logic [31:0]  exec_out_addr,
    output logic [11:0]  exec_flags,       // [0]SiLU-g [1]SiLU-m [2]ReLU [3]bias
    output logic [3:0]   exec_stride,
    output logic [3:0]   exec_pad,
    output logic [3:0]   exec_kernel,
    output logic [9:0]   exec_pconfig,     // PE_CONFIG: per-PE setup word
    output logic [5:0]   exec_shift,       // requant right shift (CONV/POOL)
    output logic [5:0]   exec_lhs_shift,   // ADD operand-A requant shift
    output logic [5:0]   exec_rhs_shift,   // ADD operand-B requant shift
    input  logic         exec_done,

    // DMA command to the DMA Controller.
    output logic         dma_valid,        // held high until dma_done
    output logic         dma_is_store,     // 0 = DMA_LD, 1 = DMA_ST
    output logic [31:0]  dma_dram,
    output logic [31:0]  dma_sram,
    output logic [31:0]  dma_size,
    input  logic         dma_done,

    output logic         halted
);

    // FSM.
    typedef enum logic [2:0] {
        S_IDLE, S_FETCH, S_DECODE, S_EXEC, S_DMA, S_HALT
    } state_t;
    state_t state, next;

    logic [3:0] opcode;
    assign opcode = instr[127:124];

    // Latched configuration (CONFIG / ADDCFG).
    logic [15:0] r_in_h, r_in_w, r_in_c, r_out_c;
    logic [9:0]  r_pconfig;
    logic [5:0]  r_shift, r_lhs, r_rhs;

    // Latched EXEC / DMA fields.
    logic [1:0]  r_op;
    logic [31:0] r_in, r_wgt, r_out, r_dram, r_sram, r_size;
    logic [11:0] r_flags;
    logic [3:0]  r_stride, r_pad, r_kernel;
    logic        r_is_store;

    // Next-state logic.
    always_comb begin
        next = state;
        case (state)
            S_IDLE:   if (start)       next = S_FETCH;
            S_FETCH:  if (instr_valid) next = S_DECODE;
            S_DECODE:
                case (opcode)
                    `OP_CONV, `OP_POOL, `OP_ADD: next = S_EXEC;
                    `OP_DMA_LD, `OP_DMA_ST:      next = S_DMA;
                    `OP_HALT:                    next = S_HALT;
                    default:                     next = S_FETCH;  // CONFIG / ADDCFG
                endcase
            S_EXEC:   if (exec_done)   next = S_FETCH;
            S_DMA:    if (dma_done)    next = S_FETCH;
            S_HALT:                    next = S_HALT;
            default:                   next = S_IDLE;
        endcase
    end

    // Sequential state and register latching.
    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            pc      <= 16'd0;
            r_in_h  <= '0; r_in_w <= '0; r_in_c <= '0; r_out_c <= '0;
            r_pconfig <= '0;
            r_shift <= '0; r_lhs  <= '0; r_rhs  <= '0;
        end else begin
            state <= next;
            case (state)
                S_DECODE: begin
                    case (opcode)
                        `OP_CONFIG: begin
                            r_in_h  <= `CFG_IN_H(instr);
                            r_in_w  <= `CFG_IN_W(instr);
                            r_in_c  <= `CFG_IN_C(instr);
                            r_out_c <= `CFG_OUT_C(instr);
                            r_pconfig <= `CFG_PCONFIG(instr);
                            r_shift <= `CFG_SHIFT(instr);
                            pc      <= pc + 16'd1;
                        end
                        `OP_ADDCFG: begin
                            r_lhs <= `ADDCFG_LHS(instr);
                            r_rhs <= `ADDCFG_RHS(instr);
                            pc    <= pc + 16'd1;
                        end
                        `OP_CONV, `OP_POOL, `OP_ADD: begin
                            r_op     <= (opcode == `OP_CONV) ? 2'd0 :
                                        (opcode == `OP_POOL) ? 2'd1 : 2'd2;
                            r_in     <= `EXEC_IN(instr);
                            r_wgt    <= `EXEC_WGT(instr);
                            r_out    <= `EXEC_OUT(instr);
                            r_flags  <= `EXEC_FLAGS(instr);
                            r_stride <= `EXEC_STRIDE(instr);
                            r_pad    <= `EXEC_PAD(instr);
                            r_kernel <= `EXEC_KERNEL(instr);
                        end
                        `OP_DMA_LD, `OP_DMA_ST: begin
                            r_is_store <= (opcode == `OP_DMA_ST);
                            r_dram     <= `DMA_DRAM(instr);
                            r_sram     <= `DMA_SRAM(instr);
                            r_size     <= `DMA_SIZE(instr);
                        end
                        default: ;
                    endcase
                end
                S_EXEC: if (exec_done) pc <= pc + 16'd1;
                S_DMA:  if (dma_done)  pc <= pc + 16'd1;
                default: ;
            endcase
        end
    end

    // Outputs.
    assign instr_req = (state == S_FETCH);
    assign halted    = (state == S_HALT);

    assign exec_valid     = (state == S_EXEC);
    assign exec_op        = r_op;
    assign exec_in_h      = r_in_h;
    assign exec_in_w      = r_in_w;
    assign exec_in_c      = r_in_c;
    assign exec_out_c     = r_out_c;
    assign exec_in_addr   = r_in;
    assign exec_wgt_addr  = r_wgt;
    assign exec_out_addr  = r_out;
    assign exec_flags     = r_flags;
    assign exec_stride    = r_stride;
    assign exec_pad       = r_pad;
    assign exec_kernel    = r_kernel;
    assign exec_pconfig   = r_pconfig;
    assign exec_shift     = r_shift;
    assign exec_lhs_shift = r_lhs;
    assign exec_rhs_shift = r_rhs;

    assign dma_valid    = (state == S_DMA);
    assign dma_is_store = r_is_store;
    assign dma_dram     = r_dram;
    assign dma_sram     = r_sram;
    assign dma_size     = r_size;

endmodule
