`include "define.svh"
// NPU_top: top-level integration of the YOLOv8n NPU.
//
// Wires together:
//   ICache -> Decoder -> { DMA_ctrl, PingPong_Ctrl }
//   DMA_ctrl <-> SRAM port 0 <-> external DRAM
//   ConfigLoader -> PE_array (scan chains + PE_en) once at startup
//   PingPong_Ctrl + Weight_Buffer x2 + IOMap_Buffer x2 + Line_Buffer
//                 + PE_array + OpsumCollector + PSUM_acc x16 + PPU + Add_Qint8
//   SRAM port 1 is muxed between Weight_Buffer x2 and IOMap_Buffer x2
//   (the MVP controller schedule guarantees only one is active at a time).
//
// External interface: a start pulse, a halted flag, and a DRAM port the
// testbench / system supplies (input image, weights, backbone outputs).
module NPU_top (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,
    output logic         halted,

    // DRAM interface.
    output logic         dram_en,
    output logic         dram_we,
    output logic [31:0]  dram_addr,
    output logic [`DATA_BITS-1:0] dram_wdata,
    input  logic [`DATA_BITS-1:0] dram_rdata
);
    localparam NUM_PE = `NUMS_PE_ROW * `NUMS_PE_COL;
    localparam LANES  = `NUMS_PE_COL;

    // ICache <-> Decoder.
    logic [15:0]  pc;
    logic         instr_req;
    logic [127:0] instr;
    logic         instr_valid;

    // Decoder -> PingPong_Ctrl.
    logic         exec_valid;
    logic [1:0]   exec_op;
    logic [15:0]  exec_in_h, exec_in_w, exec_in_c, exec_out_c;
    logic [31:0]  exec_in_addr, exec_wgt_addr, exec_out_addr;
    logic [11:0]  exec_flags;
    logic [3:0]   exec_stride, exec_pad, exec_kernel;
    logic [9:0]   exec_pconfig;
    logic [5:0]   exec_shift, exec_lhs_shift, exec_rhs_shift;
    logic         exec_done;

    // Decoder -> DMA_ctrl.
    logic         dma_valid, dma_is_store;
    logic [31:0]  dma_dram, dma_sram, dma_size;
    logic         dma_done;

    // ConfigLoader -> PE_array.
    logic                              set_XID, set_YID, set_LN;
    logic [`XID_BITS-1:0]              ifmap_XID_scan_in, filter_XID_scan_in,
                                       ipsum_XID_scan_in, opsum_XID_scan_in;
    logic [`YID_BITS-1:0]              ifmap_YID_scan_in, filter_YID_scan_in,
                                       ipsum_YID_scan_in, opsum_YID_scan_in;
    logic [`NUMS_PE_ROW-2:0]           LN_config_in;
    logic [NUM_PE-1:0]                 PE_en;
    logic [NUM_PE-1:0]                 PE_en_gated; // PE_en pulsed only during S_PE_CONFIG
    logic                              ifmap_en;    // from PingPong: true only in S_IFMAP
    logic                              cfg_done;

    // PingPong_Ctrl -> buffers.
    logic                              wb_fill_start, wb_fill_done, wb_sel;
    logic [`SRAM_ADDR_BITS-1:0]        wb_fill_addr;
    logic [31:0]                       wb_fill_bytes;

    logic                              iob_in_start, iob_in_done;
    logic [`SRAM_ADDR_BITS-1:0]        iob_in_addr;
    logic [31:0]                       iob_in_len;
    logic                              iob_out_start, iob_out_done;
    logic [`SRAM_ADDR_BITS-1:0]        iob_out_addr;
    logic [31:0]                       iob_out_len;
    logic                              iob_swap;

    logic                              lb_flush;
    logic [15:0]                       lb_row_width;
    logic [3:0]                        lb_kernel;

    // PingPong_Ctrl -> PE array.
    logic [`CONFIG_SIZE-1:0]           pe_config;
    logic [1:0]                        glb_sel;
    logic [`XID_BITS-1:0]              ifmap_tag_X, filter_tag_X,
                                       ipsum_tag_X, opsum_tag_X;
    logic [`YID_BITS-1:0]              ifmap_tag_Y, filter_tag_Y,
                                       ipsum_tag_Y, opsum_tag_Y;

    // PingPong_Ctrl -> PPU.
    logic [5:0]                        ppu_shift;
    logic                              ppu_silu_en, ppu_maxpool_en, ppu_maxpool_init;

    // PingPong_Ctrl -> OpsumCollector.
    logic                              oc_layer_start, oc_bias_en;
    logic                              oc_pixel_init, oc_pixel_last;
    logic                              oc_layer_last;  // HIGH only on final opsum_accept
    logic [3:0]                        oc_lane_sel;

    // PingPong_Ctrl -> Add_Qint8.
    logic                              add_en;
    logic [5:0]                        add_lhs_shift, add_rhs_shift;

    // v2: PingPong drives ipsum into the GIN.
    logic                              pp_ipsum_valid;

    // SRAM (4 MiB dual-port).
    logic                              a_en, a_we;
    logic [`SRAM_ADDR_BITS-1:0]        a_addr;
    logic [`DATA_BITS-1:0]             a_wdata, a_rdata;
    logic                              b_en, b_we;
    logic [`SRAM_ADDR_BITS-1:0]        b_addr;
    logic [`DATA_BITS-1:0]             b_wdata, b_rdata;

    // Weight_Buffer x2.
    logic                              wb0_fill_done, wb1_fill_done;
    logic                              wb0_sram_en, wb1_sram_en;
    logic [`SRAM_ADDR_BITS-1:0]        wb0_sram_addr, wb1_sram_addr;
    logic [`DATA_BITS-1:0]             wb0_filter_data, wb1_filter_data;
    logic                              wb0_filter_valid, wb1_filter_valid;
    logic                              wb0_filter_ready, wb1_filter_ready;

    // IOMap_Buffer x2.
    logic                              iob0_mode_write, iob1_mode_write;
    logic                              iob0_start, iob1_start;
    logic [`SRAM_ADDR_BITS-1:0]        iob0_base_addr, iob1_base_addr;
    logic [31:0]                       iob0_length, iob1_length;
    logic                              iob0_done, iob1_done;
    logic                              iob0_sram_en, iob0_sram_we;
    logic                              iob1_sram_en, iob1_sram_we;
    logic [`SRAM_ADDR_BITS-1:0]        iob0_sram_addr, iob1_sram_addr;
    logic [`DATA_BITS-1:0]             iob0_sram_wdata, iob1_sram_wdata;
    logic [`DATA_BITS-1:0]             iob0_ifmap_data, iob1_ifmap_data;
    logic                              iob0_ifmap_valid, iob1_ifmap_valid;
    logic                              iob0_ifmap_ready, iob1_ifmap_ready;
    logic [`DATA_BITS-1:0]             iob0_ppu_data, iob1_ppu_data;
    logic                              iob0_ppu_valid, iob1_ppu_valid;
    logic                              iob0_ppu_ready, iob1_ppu_ready;

    // Line_Buffer.
    logic [`DATA_BITS-1:0]             lb_ifmap_data, lb_win_data;
    logic                              lb_ifmap_valid, lb_ifmap_ready;
    logic                              lb_win_valid, lb_win_ready;

    // GLB streams to PE_array.
    logic                              GLB_ifmap_valid,  GLB_ifmap_ready;
    logic                              GLB_filter_valid, GLB_filter_ready;
    logic                              GLB_ipsum_valid,  GLB_ipsum_ready;
    logic [`DATA_BITS-1:0]             GLB_data_in;
    logic                              GLB_opsum_valid, GLB_opsum_ready;
    logic [`DATA_BITS-1:0]             GLB_data_out;

    // OpsumCollector <-> PSUM_acc x16.
    logic signed [`PSUM_BITS-1:0]      oc_psum_data;
    logic [LANES*`PSUM_BITS-1:0]       oc_psum_bias;
    logic [LANES-1:0]                  oc_psum_init, oc_psum_accum_en, oc_psum_last;
    logic [LANES-1:0]                  oc_psum_complete;
    logic [LANES*`PSUM_BITS-1:0]       oc_psum_out_flat;

    // OpsumCollector <-> PPU.
    logic [`DATA_BITS-1:0]             oc_ppu_data_in;
    logic [7:0]                        oc_ppu_data_out;

    // OpsumCollector packed activation stream.
    logic [`DATA_BITS-1:0]             oc_act_data;
    logic                              oc_act_valid, oc_act_ready;
    logic                              oc_done;

    // Bias stream to OpsumCollector. MVP: tie off.
    logic                              bias_valid, bias_ready;
    logic signed [`PSUM_BITS-1:0]      bias_word;
    assign bias_valid = 1'b0;
    assign bias_word  = '0;

    // Instantiations.

    ICache i_cache (
        .clk(clk),
        .req(instr_req),
        .pc(pc),
        .instr(instr),
        .instr_valid(instr_valid)
    );

    Decoder i_decoder (
        .clk(clk), .rst(rst), .start(start),
        .pc(pc), .instr_req(instr_req), .instr(instr), .instr_valid(instr_valid),
        .exec_valid(exec_valid), .exec_op(exec_op),
        .exec_in_h(exec_in_h), .exec_in_w(exec_in_w),
        .exec_in_c(exec_in_c), .exec_out_c(exec_out_c),
        .exec_in_addr(exec_in_addr), .exec_wgt_addr(exec_wgt_addr),
        .exec_out_addr(exec_out_addr),
        .exec_flags(exec_flags),
        .exec_stride(exec_stride), .exec_pad(exec_pad), .exec_kernel(exec_kernel),
        .exec_pconfig(exec_pconfig),
        .exec_shift(exec_shift),
        .exec_lhs_shift(exec_lhs_shift), .exec_rhs_shift(exec_rhs_shift),
        .exec_done(exec_done),
        .dma_valid(dma_valid), .dma_is_store(dma_is_store),
        .dma_dram(dma_dram), .dma_sram(dma_sram), .dma_size(dma_size),
        .dma_done(dma_done),
        .halted(halted)
    );

    SRAM i_sram (
        .clk(clk),
        .a_en(a_en), .a_we(a_we), .a_addr(a_addr),
        .a_wdata(a_wdata), .a_rdata(a_rdata),
        .b_en(b_en), .b_we(b_we), .b_addr(b_addr),
        .b_wdata(b_wdata), .b_rdata(b_rdata)
    );

    DMA_ctrl i_dma (
        .clk(clk), .rst(rst),
        .dma_valid(dma_valid), .dma_is_store(dma_is_store),
        .dma_dram(dma_dram), .dma_sram(dma_sram), .dma_size(dma_size),
        .dma_done(dma_done),
        .dram_en(dram_en), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata), .dram_rdata(dram_rdata),
        .sram_en(a_en), .sram_we(a_we), .sram_addr(a_addr),
        .sram_wdata(a_wdata), .sram_rdata(a_rdata)
    );

    // LN_CONFIG uses default 15'h36DB: enables psum chaining across all R=3
    // rows within each PE set (bottom-up: row 2 → row 1 → row 0 → GON).
    ConfigLoader i_cfg (
        .clk(clk), .rst(rst), .start(start), .cfg_done(cfg_done),
        .set_XID(set_XID),
        .ifmap_XID_scan_in(ifmap_XID_scan_in),
        .filter_XID_scan_in(filter_XID_scan_in),
        .ipsum_XID_scan_in(ipsum_XID_scan_in),
        .opsum_XID_scan_in(opsum_XID_scan_in),
        .set_YID(set_YID),
        .ifmap_YID_scan_in(ifmap_YID_scan_in),
        .filter_YID_scan_in(filter_YID_scan_in),
        .ipsum_YID_scan_in(ipsum_YID_scan_in),
        .opsum_YID_scan_in(opsum_YID_scan_in),
        .set_LN(set_LN), .LN_config_in(LN_config_in),
        .PE_en(PE_en)
    );

    PingPong_Ctrl i_ppc (
        .clk(clk), .rst(rst),
        .exec_valid(exec_valid), .exec_op(exec_op),
        .exec_in_h(exec_in_h), .exec_in_w(exec_in_w),
        .exec_in_c(exec_in_c), .exec_out_c(exec_out_c),
        .exec_in_addr(exec_in_addr), .exec_wgt_addr(exec_wgt_addr),
        .exec_out_addr(exec_out_addr),
        .exec_flags(exec_flags),
        .exec_stride(exec_stride), .exec_pad(exec_pad), .exec_kernel(exec_kernel),
        .exec_pconfig(exec_pconfig),
        .exec_shift(exec_shift),
        .exec_lhs_shift(exec_lhs_shift), .exec_rhs_shift(exec_rhs_shift),
        .exec_done(exec_done),
        .wb_fill_start(wb_fill_start), .wb_fill_addr(wb_fill_addr),
        .wb_fill_bytes(wb_fill_bytes), .wb_fill_done(wb_fill_done),
        .wb_sel(wb_sel),
        .iob_in_start(iob_in_start), .iob_in_addr(iob_in_addr),
        .iob_in_len(iob_in_len), .iob_in_done(iob_in_done),
        .iob_out_start(iob_out_start), .iob_out_addr(iob_out_addr),
        .iob_out_len(iob_out_len), .iob_out_done(iob_out_done),
        .iob_swap(iob_swap),
        .lb_flush(lb_flush), .lb_row_width(lb_row_width), .lb_kernel(lb_kernel),
        .cfg_done(cfg_done),
        .pe_config(pe_config), .glb_sel(glb_sel),
        .ifmap_tag_X(ifmap_tag_X),   .filter_tag_X(filter_tag_X),
        .ipsum_tag_X(ipsum_tag_X),   .opsum_tag_X(opsum_tag_X),
        .ifmap_tag_Y(ifmap_tag_Y),   .filter_tag_Y(filter_tag_Y),
        .ipsum_tag_Y(ipsum_tag_Y),   .opsum_tag_Y(opsum_tag_Y),
        .glb_ifmap_ready(GLB_ifmap_ready),
        .glb_ifmap_valid(GLB_ifmap_valid),
        .glb_filter_ready(GLB_filter_ready),
        .glb_filter_valid(GLB_filter_valid),
        .glb_ipsum_ready(GLB_ipsum_ready),
        .glb_opsum_valid(GLB_opsum_valid),
        .glb_opsum_ready(GLB_opsum_ready),
        .ppu_shift(ppu_shift), .ppu_silu_en(ppu_silu_en),
        .ppu_maxpool_en(ppu_maxpool_en), .ppu_maxpool_init(ppu_maxpool_init),
        .oc_layer_start(oc_layer_start), .oc_bias_en(oc_bias_en),
        .oc_pixel_init(oc_pixel_init), .oc_pixel_last(oc_pixel_last),
        .oc_layer_last(oc_layer_last),
        .oc_lane_sel(oc_lane_sel),
        .add_en(add_en),
        .add_lhs_shift(add_lhs_shift), .add_rhs_shift(add_rhs_shift),
        .pp_ipsum_valid(pp_ipsum_valid),
        .ifmap_en(ifmap_en)
    );

    // Weight_Buffer ping-pong. wb_sel selects which instance the controller
    // refills; the other is the active reader feeding the GIN filter stream.
    Weight_Buffer wb0 (
        .clk(clk), .rst(rst),
        .fill_start(wb_fill_start & ~wb_sel),
        .fill_addr(wb_fill_addr), .fill_bytes(wb_fill_bytes),
        .fill_done(wb0_fill_done),
        .sram_en(wb0_sram_en), .sram_addr(wb0_sram_addr),
        .sram_rdata(b_rdata),
        .filter_data(wb0_filter_data),
        .filter_valid(wb0_filter_valid), .filter_ready(wb0_filter_ready)
    );
    Weight_Buffer wb1 (
        .clk(clk), .rst(rst),
        .fill_start(wb_fill_start &  wb_sel),
        .fill_addr(wb_fill_addr), .fill_bytes(wb_fill_bytes),
        .fill_done(wb1_fill_done),
        .sram_en(wb1_sram_en), .sram_addr(wb1_sram_addr),
        .sram_rdata(b_rdata),
        .filter_data(wb1_filter_data),
        .filter_valid(wb1_filter_valid), .filter_ready(wb1_filter_ready)
    );
    assign wb_fill_done = wb_sel ? wb1_fill_done : wb0_fill_done;

    // IOMap_Buffer ping-pong wiring.
    assign iob0_mode_write = iob_swap;
    assign iob1_mode_write = ~iob_swap;
    assign iob0_start      = iob_swap ? iob_out_start : iob_in_start;
    assign iob1_start      = iob_swap ? iob_in_start  : iob_out_start;
    assign iob0_base_addr  = iob_swap ? iob_out_addr  : iob_in_addr;
    assign iob1_base_addr  = iob_swap ? iob_in_addr   : iob_out_addr;
    assign iob0_length     = iob_swap ? iob_out_len   : iob_in_len;
    assign iob1_length     = iob_swap ? iob_in_len    : iob_out_len;
    assign iob_in_done     = iob_swap ? iob1_done     : iob0_done;
    assign iob_out_done    = iob_swap ? iob0_done     : iob1_done;

    IOMap_Buffer iob0 (
        .clk(clk), .rst(rst),
        .mode_write(iob0_mode_write), .start(iob0_start),
        .base_addr(iob0_base_addr), .length(iob0_length),
        .done(iob0_done),
        .sram_en(iob0_sram_en), .sram_we(iob0_sram_we),
        .sram_addr(iob0_sram_addr),
        .sram_wdata(iob0_sram_wdata), .sram_rdata(b_rdata),
        .ifmap_data(iob0_ifmap_data),
        .ifmap_valid(iob0_ifmap_valid), .ifmap_ready(iob0_ifmap_ready),
        .ppu_data(iob0_ppu_data),
        .ppu_valid(iob0_ppu_valid), .ppu_ready(iob0_ppu_ready)
    );
    IOMap_Buffer iob1 (
        .clk(clk), .rst(rst),
        .mode_write(iob1_mode_write), .start(iob1_start),
        .base_addr(iob1_base_addr), .length(iob1_length),
        .done(iob1_done),
        .sram_en(iob1_sram_en), .sram_we(iob1_sram_we),
        .sram_addr(iob1_sram_addr),
        .sram_wdata(iob1_sram_wdata), .sram_rdata(b_rdata),
        .ifmap_data(iob1_ifmap_data),
        .ifmap_valid(iob1_ifmap_valid), .ifmap_ready(iob1_ifmap_ready),
        .ppu_data(iob1_ppu_data),
        .ppu_valid(iob1_ppu_valid), .ppu_ready(iob1_ppu_ready)
    );

    // Active input/output IOMap routing.
    assign lb_ifmap_data    = iob_swap ? iob1_ifmap_data  : iob0_ifmap_data;
    assign lb_ifmap_valid   = iob_swap ? iob1_ifmap_valid : iob0_ifmap_valid;
    assign iob0_ifmap_ready = ~iob_swap & lb_ifmap_ready;
    assign iob1_ifmap_ready =  iob_swap & lb_ifmap_ready;

    assign iob0_ppu_data  = oc_act_data;
    assign iob1_ppu_data  = oc_act_data;
    assign iob0_ppu_valid =  iob_swap & oc_act_valid;
    assign iob1_ppu_valid = ~iob_swap & oc_act_valid;
    assign oc_act_ready   = iob_swap ? iob0_ppu_ready : iob1_ppu_ready;

    // Line_Buffer geometry: pull layer dims directly from the latched
    // Decoder outputs (stable while exec_valid is high). out_h is the conv
    // formula (in_h + 2*pad - kernel) / stride + 1.
    logic [15:0] lb_out_h;
    logic        lb_done;
    assign lb_out_h = ((exec_in_h + (exec_pad << 1) - exec_kernel) / exec_stride) + 16'd1;

    Line_Buffer i_lb (
        .clk(clk), .rst(rst),
        .layer_start(oc_layer_start),
        .in_h(exec_in_h), .in_w(exec_in_w), .out_h(lb_out_h),
        .kernel(exec_kernel), .stride(exec_stride), .pad(exec_pad),
        .done(lb_done),
        .ifmap_data(lb_ifmap_data),
        .ifmap_valid(lb_ifmap_valid), .ifmap_ready(lb_ifmap_ready),
        .win_data(lb_win_data),
        .win_valid(lb_win_valid), .win_ready(lb_win_ready)
    );

    // SRAM port 1 mux: priority encoder (wb > iob_in > iob_out).
    // MVP relies on the controller schedule not overlapping users.
    always_comb begin
        b_en = 1'b0; b_we = 1'b0; b_addr = '0; b_wdata = '0;
        if      (wb0_sram_en)  begin b_en = 1'b1; b_addr = wb0_sram_addr; end
        else if (wb1_sram_en)  begin b_en = 1'b1; b_addr = wb1_sram_addr; end
        else if (iob0_sram_en) begin
            b_en = 1'b1; b_we = iob0_sram_we;
            b_addr = iob0_sram_addr; b_wdata = iob0_sram_wdata;
        end else if (iob1_sram_en) begin
            b_en = 1'b1; b_we = iob1_sram_we;
            b_addr = iob1_sram_addr; b_wdata = iob1_sram_wdata;
        end
    end

    // GLB filter stream: MVP reads from the same WB it just filled (no
    // background prefetch in a single-layer test). Polarity matches the
    // wb_fill_start routing so wb_sel=0 means wb0 is both filling and
    // reading.
    assign GLB_filter_valid = wb_sel ? wb1_filter_valid : wb0_filter_valid;
    assign wb0_filter_ready = ~wb_sel & GLB_filter_ready;
    assign wb1_filter_ready =  wb_sel & GLB_filter_ready;

    // GLB ifmap stream from Line_Buffer — gated to the S_IFMAP phase only.
    // Without this gate, lb_win_valid can go high while PingPong is still in
    // S_FILTER (IOMap + Line_Buffer warm-up finishes ~30 cycles after
    // S_PE_CONFIG).  PEs that just exited WEIGHT→IF would immediately accept
    // the stray ifmap word and advance to COMPUTE, so when PingPong finally
    // reaches S_IFMAP every PE is already past IF → GLB_ifmap_ready stays 0
    // → S_IFMAP never exits.
    assign GLB_ifmap_valid = lb_win_valid && ifmap_en;
    // Gate lb_win_ready too: Line_Buffer must not advance its window outside
    // S_IFMAP.  Without this, PEs that just exited WEIGHT→IF (near the end of
    // S_FILTER) raise GLB_ifmap_ready=1, which would let the LB consume up to
    // 6 window slots before PingPong even enters S_IFMAP.  The controller
    // counter would then see lb_win_valid=0 for those missing slots and
    // time out waiting for data.
    assign lb_win_ready    = GLB_ifmap_ready && ifmap_en;

    // GLB ipsum stream: PingPong drives it during S_IPSUM phase. Data is 0
    // (the seed for the reduction), supplied via glb_sel=2 in the data mux.
    assign GLB_ipsum_valid = pp_ipsum_valid;

    // GLB data mux based on glb_sel from the controller.
    always_comb begin
        case (glb_sel)
            2'd0: GLB_data_in = lb_win_data;
            2'd1: GLB_data_in = wb_sel ? wb1_filter_data : wb0_filter_data;
            default: GLB_data_in = '0;
        endcase
    end

    // Gate PE_en: fire PEs into WEIGHT only during S_PE_CONFIG (lb_flush=1),
    // at which point pe_config is already valid so PEs latch out_ch_num correctly.
    assign PE_en_gated = lb_flush ? PE_en : '0;

    PE_array i_pe_array (
        .clk(clk), .rst(rst),
        .set_XID(set_XID),
        .ifmap_XID_scan_in(ifmap_XID_scan_in),
        .filter_XID_scan_in(filter_XID_scan_in),
        .ipsum_XID_scan_in(ipsum_XID_scan_in),
        .opsum_XID_scan_in(opsum_XID_scan_in),
        .set_YID(set_YID),
        .ifmap_YID_scan_in(ifmap_YID_scan_in),
        .filter_YID_scan_in(filter_YID_scan_in),
        .ipsum_YID_scan_in(ipsum_YID_scan_in),
        .opsum_YID_scan_in(opsum_YID_scan_in),
        .set_LN(set_LN), .LN_config_in(LN_config_in),
        .PE_en(PE_en_gated), .PE_config(pe_config),
        .ifmap_tag_X(ifmap_tag_X),   .ifmap_tag_Y(ifmap_tag_Y),
        .filter_tag_X(filter_tag_X), .filter_tag_Y(filter_tag_Y),
        .ipsum_tag_X(ipsum_tag_X),   .ipsum_tag_Y(ipsum_tag_Y),
        .opsum_tag_X(opsum_tag_X),   .opsum_tag_Y(opsum_tag_Y),
        .GLB_ifmap_valid(GLB_ifmap_valid),
        .GLB_ifmap_ready(GLB_ifmap_ready),
        .GLB_filter_valid(GLB_filter_valid),
        .GLB_filter_ready(GLB_filter_ready),
        .GLB_ipsum_valid(GLB_ipsum_valid),
        .GLB_ipsum_ready(GLB_ipsum_ready),
        .GLB_data_in(GLB_data_in),
        .GLB_opsum_valid(GLB_opsum_valid),
        .GLB_opsum_ready(GLB_opsum_ready),
        .GLB_data_out(GLB_data_out)
    );

    // PSUM_acc x16, generated per lane.
    genvar gi;
    generate
        for (gi = 0; gi < LANES; gi++) begin : PSUM
            logic signed [`PSUM_BITS-1:0] this_out;
            PSUM_acc i_psum (
                .clk(clk), .rst(rst),
                .init(oc_psum_init[gi]),
                .accum_en(oc_psum_accum_en[gi]),
                .last(oc_psum_last[gi]),
                .psum_in(oc_psum_data),
                .bias_in(oc_psum_bias[gi*`PSUM_BITS +: `PSUM_BITS]),
                .psum_out(this_out),
                .complete(oc_psum_complete[gi])
            );
            assign oc_psum_out_flat[gi*`PSUM_BITS +: `PSUM_BITS] = this_out;
        end
    endgenerate

    OpsumCollector i_oc (
        .clk(clk), .rst(rst),
        .layer_start(oc_layer_start), .bias_en(oc_bias_en),
        .pixel_init(oc_pixel_init), .pixel_last(oc_pixel_last),
        .layer_last(oc_layer_last),
        .lane_sel(oc_lane_sel),
        .bias_valid(bias_valid), .bias_word(bias_word),
        .bias_ready(bias_ready),
        .opsum_valid(GLB_opsum_valid), .opsum_data($signed(GLB_data_out)),
        .opsum_ready(GLB_opsum_ready),
        .psum_data(oc_psum_data),
        .psum_bias(oc_psum_bias),
        .psum_init(oc_psum_init),
        .psum_accum_en(oc_psum_accum_en),
        .psum_last(oc_psum_last),
        .psum_complete(oc_psum_complete),
        .psum_out_flat(oc_psum_out_flat),
        .ppu_data_in(oc_ppu_data_in), .ppu_data_out(oc_ppu_data_out),
        .act_data(oc_act_data), .act_valid(oc_act_valid),
        .act_ready(oc_act_ready),
        .done(oc_done)
    );

    // PPU (single shared, combinational).
    PPU i_ppu (
        .clk(clk), .rst(rst),
        .data_in(oc_ppu_data_in),
        .shift(ppu_shift),
        .silu_en(ppu_silu_en),
        .maxpool_en(ppu_maxpool_en),
        .maxpool_init(ppu_maxpool_init),
        .data_out(oc_ppu_data_out)
    );

    // Add_Qint8 instantiated but not wired into the datapath in the MVP.
    // The residual ADD path needs a streaming wrapper around it (read two
    // SRAM operands element-wise, write result). Deferred to v2.
    logic [7:0] add_unused;
    Add_Qint8 i_add (
        .a_in(8'd128), .b_in(8'd128),
        .lhs_shift(add_lhs_shift), .rhs_shift(add_rhs_shift),
        .data_out(add_unused)
    );

endmodule
