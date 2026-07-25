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
    
    // 【修改】：单数据流输出
    output reg [31:0] sa_north_in,
    output reg [31:0] sa_west_in,
    output reg sa_enable,
    
    input wire [63:0] sa_result_flat [0:SA_SIZE*SA_SIZE-1]
);

localparam IDLE = 3'd0, LOAD_INPUT = 3'd1, SETUP_SA = 3'd2, COMPUTE = 3'd3, 
           WAIT_RESULT = 3'd4, READ_RESULT = 3'd5, STORE_OUTPUT = 3'd6, DONE_STATE = 3'd7;

reg [2:0] state;
reg [5:0] load_cnt;
reg [2:0] res_byte_idx;
reg [3:0] res_idx;
reg [5:0] compute_cnt;
reg [5:0] matrix_cnt; // 追踪当前输入的矩阵元素周期 (0 ~ 15)
reg [31:0] input_buffer [0:31];
reg [63:0] current_result;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE; done <= 0; lsu_read_req <= 0; lsu_write_req <= 0; sa_enable <= 0;
        load_cnt <= 0; compute_cnt <= 0; matrix_cnt <= 0; res_byte_idx <= 0; res_idx <= 0;
        current_result <= 64'd0;
        sa_north_in <= 32'd0;
        sa_west_in  <= 32'd0;
    end else begin
        lsu_read_req <= 0; lsu_write_req <= 0; sa_enable <= 0; done <= 0;
        
        case (state)
            IDLE: begin
                if (start_compute) begin 
                    state <= LOAD_INPUT; 
                    load_cnt <= 0; 
                end
            end
            
            LOAD_INPUT: begin
                lsu_read_req <= 1;
                lsu_read_addr <= input_base + load_cnt;
                if (lsu_read_ready) begin
                    input_buffer[load_cnt >> 2][(load_cnt & 3) * 8 +: 8] <= lsu_read_data;
                    if (load_cnt == 31) begin
                        state <= SETUP_SA;
                    end else begin
                        load_cnt <= load_cnt + 1;
                    end
                end
            end
            
            SETUP_SA: begin
                state <= COMPUTE; 
                compute_cnt <= 0; 
                matrix_cnt <= 0; 
            end
            
            COMPUTE: begin
                sa_enable <= 1;
                
                // 【重新设计的输入调度】
                // 1. west_in (A矩阵): 按行主序连续输入 (索引 0 ~ 15)
                sa_west_in <= input_buffer[matrix_cnt];
                
                // 2. north_in (B矩阵): 按列主序连续输入 (索引 16 ~ 31)
                // 公式: 16 + (行索引 * 4) + 列索引 
                // 其中 行索引 = matrix_cnt % 4, 列索引 = matrix_cnt / 4
                sa_north_in <= input_buffer[16 + (matrix_cnt % 4) * 4 + (matrix_cnt / 4)];
                
                matrix_cnt <= matrix_cnt + 1;
                compute_cnt <= compute_cnt + 1;
                
                // 4x4 矩阵需要 16 个周期完成所有元素的斜向注入
                if (matrix_cnt == 16) begin 
                    state <= WAIT_RESULT;
                end
            end
            
            WAIT_RESULT: begin
                // 输入完成后，关闭 enable 停止累加，并输入 0。
                // 0 会继续向下/向右传递，而 result 保持不变，避免 X 态或无效累加污染。
                sa_enable <= 0;
                sa_north_in <= 32'd0;
                sa_west_in  <= 32'd0;
                compute_cnt <= compute_cnt + 1;
                
                // 等待额外的 8 个周期，确保最后一个注入的元素 (t=15) 
                // 有足够时间流动到 PE33 (需要 6 步) 并完成寄存器更新
                if (compute_cnt == 16 + 8 - 1) begin 
                    state <= READ_RESULT;
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
                $display("TIME=%0t current_result=%h res_byte=%d",
                    $time, current_result, res_byte_idx);
                
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
