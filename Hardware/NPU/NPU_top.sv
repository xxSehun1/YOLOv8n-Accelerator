`include "define.svh"
// NPU_top: top-level wrapper.
//
// Wires together:
//   ICache -> Decoder -> { DMA_ctrl, PingPong_Ctrl }
//   DMA_ctrl <-> SRAM (port 0) <-> DRAM
//   ConfigLoader -> PE_array (scan chains, PE_en) at startup
//   PingPong_Ctrl + Weight_Buffer x2 + IOMap_Buffer x2 + Line_Buffer
//                 + PE_array + OpsumCollector + PSUM_acc x16 + PPU + Add_Qint8
//   SRAM (port 1) <-> the compute buffers
//
// External interface: a start pulse, a halted flag, and a DRAM port the
// testbench / system supplies (input image, weights, backbone outputs).
module NPU_top (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,                  // begin program execution
    output logic         halted,                 // program reached HALT

    // DRAM interface (off-chip, supplied by the system / testbench).
    output logic         dram_en,
    output logic         dram_we,
    output logic [31:0]  dram_addr,
    output logic [`DATA_BITS-1:0] dram_wdata,
    input  logic [`DATA_BITS-1:0] dram_rdata
);
    // TODO: instantiate and connect ICache, Decoder, DMA_ctrl, SRAM,
    // ConfigLoader, PingPong_Ctrl, Weight_Buffer[2], IOMap_Buffer[2],
    // Line_Buffer, PE_array, OpsumCollector, PSUM_acc[16], PPU, Add_Qint8.
    // Decoder <-> Controller / DMA per the interfaces in Decoder.sv.
endmodule
