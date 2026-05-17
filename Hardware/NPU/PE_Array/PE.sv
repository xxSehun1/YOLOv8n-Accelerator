`include "define.svh"
module PE (
    input clk,
    input rst,
    input PE_en,
    input [`CONFIG_SIZE-1:0] i_config,
    input [`DATA_BITS-1:0] ifmap,
    input [`DATA_BITS-1:0] filter,
    input [`DATA_BITS-1:0] ipsum,
    input ifmap_valid,
    input filter_valid,
    input ipsum_valid,
    input opsum_ready,
    output logic [`DATA_BITS-1:0] opsum,
    output logic ifmap_ready,
    output logic filter_ready,
    output logic ipsum_ready,
    output logic opsum_valid
);
/* TODO: Start writing your implementation here */


    // FSM States
    localparam IDLE    = 3'd0;
    localparam WEIGHT  = 3'd1;
    localparam IF = 3'd2;
    localparam COMPUTE    = 3'd3;
    localparam SEND    = 3'd4;

    logic [2:0] state, next_state;

    logic [4:0] out_ch_num; 
    logic [`DATA_BITS-1:0] w_buf [0:31][0:2]; 
    logic [`DATA_BITS-1:0] out_buf [0:31];
    logic [`DATA_BITS-1:0] if_reg [0:2];

    logic [4:0] w_ch_cnt;
    logic [1:0] w_col_cnt;
    logic [1:0] if_cnt;
    logic [4:0] ip_ch_cnt;
    logic [4:0] op_ch_cnt;
    logic is_first;

    logic [`DATA_BITS-1:0] mac_val; 

    // Next state logic
    always_comb begin
        next_state = state; 
        case (state)
            IDLE: begin
                if (PE_en) next_state = WEIGHT;
            end
            WEIGHT: begin
                if (filter_valid && filter_ready && w_col_cnt == 2 && w_ch_cnt == out_ch_num)
                    next_state = IF;
            end
            IF: begin
                if (ifmap_valid && ifmap_ready) begin
                    if (is_first && if_cnt == 2) next_state = COMPUTE;
                    else if (!is_first && if_cnt == 0) next_state = COMPUTE;
                end
            end
            COMPUTE: begin
                if (ipsum_valid && ipsum_ready && ip_ch_cnt == out_ch_num)
                    next_state = SEND;
            end
            SEND: begin
                if (opsum_valid && opsum_ready && op_ch_cnt == out_ch_num)
                    next_state = IF; 
            end
            default: next_state = IDLE;
        endcase
    end

    // Sequential logic
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            is_first <= 1'b1;
            w_ch_cnt <= 0; 
            w_col_cnt <= 0;
            if_cnt <= 0; 
            ip_ch_cnt <= 0; 
            op_ch_cnt <= 0;
            out_ch_num <= 0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    if (PE_en) begin
                        out_ch_num <= {2'b00, i_config[9:7]}; 
                        is_first <= 1'b1;
                        w_ch_cnt <= 0; 
                        w_col_cnt <= 0; 
                        if_cnt <= 0;
                    end
                end

                WEIGHT: begin
                    if (filter_valid && filter_ready) begin
                        w_buf[w_ch_cnt][w_col_cnt] <= filter;
                        if (w_col_cnt == 2) begin
                            w_col_cnt <= 0;
                            if (w_ch_cnt == out_ch_num) w_ch_cnt <= 0;
                            else w_ch_cnt <= w_ch_cnt + 1;
                        end else begin
                            w_col_cnt <= w_col_cnt + 1;
                        end
                    end
                end

                IF: begin
                    if (ifmap_valid && ifmap_ready) begin
                        // shift ifmap
                        if_reg[0] <= if_reg[1];
                        if_reg[1] <= if_reg[2];
                        if_reg[2] <= ifmap; 

                        if (is_first && if_cnt == 2) begin
                            is_first <= 1'b0; 
                            if_cnt <= 0;
                        end else if (!is_first && if_cnt == 0) begin
                            if_cnt <= 0;       
                        end else begin
                            if_cnt <= if_cnt + 1;
                        end
                    end
                end

                COMPUTE: begin
                    if (ipsum_valid && ipsum_ready) begin
                        out_buf[ip_ch_cnt] <= mac_val; 
                        if (ip_ch_cnt == out_ch_num) ip_ch_cnt <= 0;
                        else ip_ch_cnt <= ip_ch_cnt + 1;
                    end
                end

                SEND: begin
                    if (opsum_valid && opsum_ready) begin
                        if (op_ch_cnt == out_ch_num) op_ch_cnt <= 0;
                        else op_ch_cnt <= op_ch_cnt + 1;
                    end
                end
                default: ;
            endcase
        end
    end

    // MAC calculation
    logic signed [31:0] temp_mac; 
    logic signed [8:0] s_ifmap;
    logic signed [7:0] s_weight;

    always_comb begin
        temp_mac = $signed(ipsum); 
        
        for (int i = 0; i < 3; i = i + 1) begin
            for (int j = 0; j < 4; j = j + 1) begin
                // sub 128 for zero point
                s_ifmap = $signed({1'b0, if_reg[i][j*8 +: 8]}) - 9'sd128; 
                s_weight = $signed(w_buf[ip_ch_cnt][i][j*8 +: 8]);
                
                temp_mac = temp_mac + (s_ifmap * s_weight);
            end
        end
        mac_val = temp_mac; 
    end

    assign filter_ready = (state == WEIGHT);
    assign ifmap_ready  = (state == IF);
    assign ipsum_ready  = (state == COMPUTE);

    assign opsum_valid  = (state == SEND);
    assign opsum        = (state == SEND) ? out_buf[op_ch_cnt] : '0;

/* TODO: End of implementation */
endmodule
