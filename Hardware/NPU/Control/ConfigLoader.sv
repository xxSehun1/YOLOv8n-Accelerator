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
    always_comb begin
        next = state;
        case (state)
            S_IDLE:     if (start)                  next = S_SCAN_XID;
            S_SCAN_XID: if (cnt == NUM_PE - 1)      next = S_SCAN_YID;
            S_SCAN_YID: if (cnt == NUM_PE - 1)      next = S_SCAN_LN;
            S_SCAN_LN:                              next = S_DONE;
            S_DONE:                                 next = S_DONE;
            default:                                next = S_IDLE;
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


    logic [ROM_W-1:0] cur;
    assign cur = scan_rom[cnt];

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
