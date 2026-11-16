`default_nettype none
`timescale 1ns/1ns

module systolic_adapter #(
    parameter SA_SIZE = 4
)(
    input wire clk,
    input wire reset,
    input wire start_compute,
    output reg done,
    input wire [7:0] input_base,
    input wire [7:0] output_base,
    
    output reg lsu_read_req,
    output reg [7:0] lsu_read_addr,
    input wire [7:0] lsu_read_data, 
    input wire lsu_read_ready,
    
    output reg lsu_write_req,
    output reg [7:0] lsu_write_addr,
    output reg [7:0] lsu_write_data,
    input wire lsu_write_ready,
    
    output reg [31:0] sa_north [0:SA_SIZE-1],
    output reg [31:0] sa_west  [0:SA_SIZE-1],
    output reg sa_enable,
    
    input wire [63:0] sa_result_flat [0:SA_SIZE*SA_SIZE-1]
);

localparam IDLE = 3'd0, LOAD_INPUT = 3'd1, SETUP_SA = 3'd2, COMPUTE = 3'd3, 
           WAIT_RESULT = 3'd4, READ_RESULT = 3'd5, STORE_OUTPUT = 3'd6, DONE_STATE = 3'd7;

reg [2:0] state;
reg [6:0] load_cnt; // 【修复1】：改为 7-bit，支持 0~127
reg [2:0] res_byte_idx;
reg [3:0] res_idx;
reg [5:0] compute_cnt;
reg [63:0] current_result;
reg [31:0] input_buffer [0:31];
reg [31:0] temp_word; // 【修复2】：新增临时组装寄存器

integer i, j;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE; done <= 0; lsu_read_req <= 0; lsu_write_req <= 0; sa_enable <= 0;
        load_cnt <= 0; compute_cnt <= 0; res_byte_idx <= 0; res_idx <= 0;
        current_result <= 64'd0;
        temp_word <= 32'd0; // 【修复2】：reset 时清零
        for (i = 0; i < SA_SIZE; i = i + 1) begin
            sa_north[i] <= 32'd0;
            sa_west[i]  <= 32'd0;
        end
    end else begin
        lsu_read_req <= 0; lsu_write_req <= 0; sa_enable <= 0; done <= 0;
        
       case (state)
            IDLE: begin
                if (start_compute) begin 
                    state <= LOAD_INPUT; 
                    load_cnt <= 0; 
                    // 【关键修复 1】：在刚启动时，就把起始地址提前放上总线
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
                            temp_word[31:24]   <= lsu_read_data;
                            input_buffer[load_cnt >> 2] <= {lsu_read_data, temp_word[23:0]};
                        end
                    endcase

                    if (load_cnt == 7'd127) begin
                        state <= SETUP_SA;
                    end else begin
                        load_cnt <= load_cnt + 1'b1;
                        // 【关键修复 2】：仅在成功读取一个字节的同一周期，精准地把请求地址推到下一个字节
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

                // 【修复2】：West 输入 A，必须呈阶梯状 Skew (延迟 i 个周期)
                for (i = 0; i < SA_SIZE; i = i + 1) begin
                    if (compute_cnt >= i && compute_cnt < i + SA_SIZE)
                        sa_west[i] <= input_buffer[i * SA_SIZE + (compute_cnt - i)];
                    else
                        sa_west[i] <= 32'd0;
                end

                // 【修复2】：North 输入 B，必须呈阶梯状 Skew (延迟 j 个周期)
                for (j = 0; j < SA_SIZE; j = j + 1) begin
                    if (compute_cnt >= j && compute_cnt < j + SA_SIZE)
                        sa_north[j] <= input_buffer[16 + (compute_cnt - j) * SA_SIZE + j];
                    else
                        sa_north[j] <= 32'd0;
                end

                // 一共需要喂 4 轮数据，加上倾斜的 3 个周期，总共 7 个周期 (0~6)
                if (compute_cnt == 6) begin
                    state <= WAIT_RESULT;
                    compute_cnt <= 0; // 复位 counter 给等待状态用
                end else begin
                    compute_cnt <= compute_cnt + 1;
                end
            end
            
            WAIT_RESULT: begin
                // 【修复3】：千万不能设为 0！阵列内部的数据还在流动，必须保持时钟/使能！
                sa_enable <= 1; 
                
                // 停止喂新数据，只喂 0
                for (i = 0; i < SA_SIZE; i = i + 1) begin
                    sa_west[i]  <= 32'd0;
                    sa_north[i] <= 32'd0;
                end

                // 等待波浪流出右下角的 PE (至少需要额外 7~8 个周期)
                if (compute_cnt == 14) begin 
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
                $display("RESULT[%0d]=%h", res_idx, sa_result_flat[res_idx]);				    
            end
            
            STORE_OUTPUT: begin
                lsu_write_req <= 1;
                lsu_write_addr <= output_base + (res_idx * 8) + res_byte_idx;
                lsu_write_data <= current_result[res_byte_idx * 8 +: 8];
                
                if (lsu_write_ready) begin
                    if (res_byte_idx == 7) begin
                        res_byte_idx <= 0;
                        if (res_idx == 15) begin
                            state <= DONE_STATE;
                        end else begin
                            res_idx <= res_idx + 1;
                            current_result <= sa_result_flat[res_idx + 1];
                            $display("RESULT[%0d]=%h", res_idx + 1, sa_result_flat[res_idx + 1]);
                        end
                    end else begin
                        res_byte_idx <= res_byte_idx + 1;
                    end
                end
            end
            
            DONE_STATE: begin 
                done <= 1; 
                state <= IDLE; 
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule
`default_nettype wire
