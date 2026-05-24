`include "define.svh"


module ConfigLoader #(
    parameter NUM_PE   = `NUMS_PE_ROW * `NUMS_PE_COL,
    parameter SCAN_HEX = "shared_config.hex",

    parameter [`NUMS_PE_ROW-2:0] LN_CONFIG_INIT = 15'h36DB,

    parameter [NUM_PE-1:0]       PE_EN_INIT = {{16{1'b0}}, {240{1'b1}}}
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic cfg_done,

    // Scan-chain drive to PE_array.
    output logic                    set_XID,
    output logic [`XID_BITS-1:0]    ifmap_XID_scan_in,
    output logic [`XID_BITS-1:0]    filter_XID_scan_in,
    output logic [`XID_BITS-1:0]    ipsum_XID_scan_in,
    output logic [`XID_BITS-1:0]    opsum_XID_scan_in,

    output logic                    set_YID,
    output logic [`YID_BITS-1:0]    ifmap_YID_scan_in,
    output logic [`YID_BITS-1:0]    filter_YID_scan_in,
    output logic [`YID_BITS-1:0]    ipsum_YID_scan_in,
    output logic [`YID_BITS-1:0]    opsum_YID_scan_in,

    output logic                    set_LN,
    output logic [`NUMS_PE_ROW-2:0] LN_config_in,

    // Static PE-enable mask to PE_array.
    output logic [NUM_PE-1:0]       PE_en
);
    localparam int X = `XID_BITS;
    localparam int Y = `YID_BITS;
    localparam int ROM_W = 4*X + 4*Y;
    localparam int CNT_W = $clog2(NUM_PE + 1);

    // Per-PE scan ROM, loaded once from SCAN_HEX at elaboration.
    logic [ROM_W-1:0] scan_rom [0:NUM_PE-1];

    initial $readmemh(SCAN_HEX, scan_rom);

    // FSM state.
    typedef enum logic [2:0] {
        S_IDLE, S_SCAN_XID, S_SCAN_YID, S_SCAN_LN, S_DONE
    } state_t;
    state_t state, next;

    // Scan-entry counter (0..NUM_PE-1 during scan states).
    logic [CNT_W-1:0] cnt;

    // Next-state logic.
    //   XID scan chain has NUM_PE registers (one per PE).
    //   YID scan chain has NUMS_PE_ROW registers (one per row -- YID is
    //   shared across all PEs in a row, confirmed against lab-3 tb_array.cpp).
    always_comb begin
        next = state;
        case (state)
            S_IDLE:     if (start)                          next = S_SCAN_XID;
            S_SCAN_XID: if (cnt == NUM_PE - 1)              next = S_SCAN_YID;
            S_SCAN_YID: if (cnt == `NUMS_PE_ROW - 1)         next = S_SCAN_LN;
            S_SCAN_LN:                                      next = S_DONE;
            S_DONE:                                         next = S_DONE;
            default:                                        next = S_IDLE;
        endcase
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            cnt   <= '0;
        end else begin
            state <= next;
            if (state != next) begin
                cnt <= '0;
            end else if (state == S_SCAN_XID || state == S_SCAN_YID) begin
                cnt <= cnt + 1'b1;
            end
        end
    end


    // Scan-chain convention (verified by PE_array_tb): the LAST scanned-in
    // value lands at PE[0]; the FIRST scanned-in value lands at the end of
    // the chain (PE[NUM_PE-1] for XID, row[NUMS_PE_ROW-1] for YID).
    //   XID phase: feed scan_rom[NUM_PE-1-cnt]; gen_shared_hex packs every PE
    //              with its own XIDs, so PE[i] receives scan_rom[i] when the
    //              chain settles.
    //   YID phase: feed scan_rom[(NUMS_PE_ROW-1-cnt) * NUMS_PE_COL]; YID is
    //              row-shared so all PEs in a row carry the same YID values
    //              in their scan_rom entry. We read column 0 of each row.
    logic [ROM_W-1:0] cur;
    always_comb begin
        if (state == S_SCAN_YID)
            cur = scan_rom[(`NUMS_PE_ROW - 1 - cnt) * `NUMS_PE_COL];
        else
            cur = scan_rom[NUM_PE - 1 - cnt];
    end

    assign ifmap_XID_scan_in  = cur[0       +: X];
    assign filter_XID_scan_in = cur[  X     +: X];
    assign ipsum_XID_scan_in  = cur[2*X     +: X];
    assign opsum_XID_scan_in  = cur[3*X     +: X];
    assign ifmap_YID_scan_in  = cur[4*X     +: Y];
    assign filter_YID_scan_in = cur[4*X+  Y +: Y];
    assign ipsum_YID_scan_in  = cur[4*X+2*Y +: Y];
    assign opsum_YID_scan_in  = cur[4*X+3*Y +: Y];

    assign set_XID = (state == S_SCAN_XID);
    assign set_YID = (state == S_SCAN_YID);
    assign set_LN  = (state == S_SCAN_LN);

    // LN_CONFIG and PE_en are static
    assign LN_config_in = LN_CONFIG_INIT;
    assign PE_en        = PE_EN_INIT;

    assign cfg_done = (state == S_DONE);

endmodule
