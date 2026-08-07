`default_nettype none
`timescale 1ns/1ns

module systolic_adapter #(
    parameter SA_SIZE    = 32,
    parameter ADDR_WIDTH = 16
)(
    input wire clk,
    input wire reset,
    input wire start_compute,
    output reg done,
    input wire [ADDR_WIDTH-1:0] input_base,
    input wire [ADDR_WIDTH-1:0] output_base,

    output reg lsu_read_req,
    output reg [ADDR_WIDTH-1:0] lsu_read_addr,
    input wire [7:0] lsu_read_data,
    input wire lsu_read_ready,

    output reg lsu_write_req,
    output reg [ADDR_WIDTH-1:0] lsu_write_addr,
    output reg [7:0] lsu_write_data,
    input wire lsu_write_ready,

    output reg [31:0] sa_north [0:SA_SIZE-1],
    output reg [31:0] sa_west  [0:SA_SIZE-1],
    output reg sa_enable,

    input wire [63:0] sa_result_flat [0:SA_SIZE*SA_SIZE-1]
);

// ============ 参数化常数 ============
localparam NUM_ELEMENTS     = SA_SIZE * SA_SIZE;           
localparam NUM_INPUT_WORDS  = 2 * NUM_ELEMENTS;            
localparam NUM_INPUT_BYTES  = NUM_INPUT_WORDS * 4;         
localparam NUM_OUTPUT_WORDS = NUM_ELEMENTS;                

localparam IDLE        = 3'd0;
localparam LOAD_INPUT  = 3'd1;
localparam SETUP_SA    = 3'd2;
localparam COMPUTE     = 3'd3;
localparam WAIT_RESULT = 3'd4;
localparam READ_RESULT = 3'd5;
localparam STORE_OUTPUT= 3'd6;
localparam DONE_STATE  = 3'd7;

reg [2:0]                state;
// 【优化】：直接固定为 16-bit，支持最大 65535 字节/元素，彻底避免 $clog2 边界溢出
reg [15:0]               load_cnt;
reg [2:0]                res_byte_idx;
reg [15:0]               res_idx;
reg [15:0]               compute_cnt;
reg [63:0]               current_result;
reg [31:0]               input_buffer [0:NUM_INPUT_WORDS-1]; 
reg [31:0]               temp_word;

integer i, j;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE; done <= 0;
        lsu_read_req <= 0; lsu_write_req <= 0; sa_enable <= 0;
        load_cnt <= 0; compute_cnt <= 0;
        res_byte_idx <= 0; res_idx <= 0;
        current_result <= 64'd0;
        temp_word <= 32'd0;
        for (i = 0; i < SA_SIZE; i = i + 1) begin
            sa_north[i] <= 32'd0;
            sa_west[i]  <= 32'd0;
        end
    end else begin
        lsu_read_req <= 0; lsu_write_req <= 0;
        sa_enable <= 0; done <= 0;

        case (state)
            IDLE: begin
                if (start_compute) begin
                    state <= LOAD_INPUT;
                    load_cnt <= 0;
                    lsu_read_addr <= input_base;
                end
            end

            LOAD_INPUT: begin
                lsu_read_req <= 1;
                if (lsu_read_ready) begin
                    case (load_cnt[1:0])
                        2'd0: temp_word[7:0]   <= lsu_read_data;
                        2'd1: temp_word[15:8]  <= lsu_read_data;
                        2'd2: temp_word[23:16] <= lsu_read_data;
                        2'd3: begin
                            temp_word[31:24] <= lsu_read_data;
                            input_buffer[load_cnt >> 2] <= {lsu_read_data, temp_word[23:0]};
                        end
                    endcase

                    if (load_cnt == NUM_INPUT_BYTES - 1) begin
                        state <= SETUP_SA;
                    end else begin
                        load_cnt <= load_cnt + 1'b1;
                        lsu_read_addr <= input_base + load_cnt + 1'b1;
                    end
                end
            end

            SETUP_SA: begin
                state <= COMPUTE;
                compute_cnt <= 0;
            end

            COMPUTE: begin
                sa_enable <= 1;

                for (i = 0; i < SA_SIZE; i = i + 1) begin
                    if (compute_cnt >= i && compute_cnt < i + SA_SIZE)
                        sa_west[i] <= input_buffer[i * SA_SIZE + (compute_cnt - i)];
                    else
                        sa_west[i] <= 32'd0;
                end

                for (j = 0; j < SA_SIZE; j = j + 1) begin
                    if (compute_cnt >= j && compute_cnt < j + SA_SIZE)
                        sa_north[j] <= input_buffer[NUM_ELEMENTS + (compute_cnt - j) * SA_SIZE + j];
                    else
                        sa_north[j] <= 32'd0;
                end

                if (compute_cnt == 2 * SA_SIZE - 2) begin
                    state <= WAIT_RESULT;
                    compute_cnt <= 0;
                end else begin
                    compute_cnt <= compute_cnt + 1;
                end
            end

            WAIT_RESULT: begin
                sa_enable <= 1;
                for (i = 0; i < SA_SIZE; i = i + 1) begin
                    sa_west[i]  <= 32'd0;
                    sa_north[i] <= 32'd0;
                end

                if (compute_cnt == 4 * SA_SIZE - 2) begin
                    state <= READ_RESULT;
                end else begin
                    compute_cnt <= compute_cnt + 1;
                end
            end

            READ_RESULT: begin
                res_byte_idx <= 0;
                res_idx <= 0;
                current_result <= sa_result_flat[0];
                state <= STORE_OUTPUT;
            end

            STORE_OUTPUT: begin
                lsu_write_req  <= 1;
                lsu_write_addr <= output_base + (res_idx * 8) + res_byte_idx;
                lsu_write_data <= current_result[res_byte_idx * 8 +: 8];

                if (lsu_write_ready) begin
                    if (res_byte_idx == 7) begin
                        res_byte_idx <= 0;
                        if (res_idx == NUM_OUTPUT_WORDS - 1) begin
                            state <= DONE_STATE;
                        end else begin
                            res_idx <= res_idx + 1;
                            current_result <= sa_result_flat[res_idx + 1];
                        end
                    end else begin
                        res_byte_idx <= res_byte_idx + 1;
                    end
                end
            end

            DONE_STATE: begin
                done  <= 1;
                state <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
`default_nettype wire
