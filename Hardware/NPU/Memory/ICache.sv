`include "define.svh"
// ICache: instruction memory.
//
// Holds the assembled program (npu_program.hex). Combinational read on pc, as
// assumed by the Decoder.
module ICache #(
    parameter DEPTH = 4096                       // 64 KiB / 16 B per instr
)(
    input  logic         clk,
    input  logic         req,                    // Decoder asserts to fetch
    input  logic [15:0]  pc,                      // instruction index
    output logic [127:0] instr,                   // 128-bit instruction
    output logic         instr_valid
);
    // Program storage; each line of npu_program.hex is one 128-bit instruction.
    logic [127:0] mem [0:DEPTH-1];

    initial $readmemh("npu_program.hex", mem);

    // Combinational read on pc (Decoder samples instr in its DECODE state).
    assign instr       = mem[pc];
    assign instr_valid = req;
endmodule
