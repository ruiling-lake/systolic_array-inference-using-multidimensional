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
    // 【修改】：使用 1024 位 packed array
    //input wire [1023:0] sa_result_flat
    input wire [63:0] sa_result_flat [0:SA_SIZE*SA_SIZE-1]
);

localparam IDLE = 3'd0, LOAD_INPUT = 3'd1, SETUP_SA = 3'd2, COMPUTE = 3'd3, 
           WAIT_RESULT = 3'd4, READ_RESULT = 3'd5, STORE_OUTPUT = 3'd6, DONE_STATE = 3'd7;

reg [2:0] state;
reg [5:0] load_cnt;
reg [2:0] res_byte_idx;
reg [3:0] res_idx;
reg [5:0] compute_cnt;
reg [31:0] input_buffer [0:31];
reg [63:0] current_result;

always @(posedge clk) begin
    if(reset) begin
        state <= IDLE; done <= 0; lsu_read_req <= 0; lsu_write_req <= 0; sa_enable <= 0;
        load_cnt <= 0; compute_cnt <= 0; res_byte_idx <= 0; res_idx <= 0;
        current_result <= 64'd0;
    end else begin
        lsu_read_req <= 0; lsu_write_req <= 0; sa_enable <= 0; done <= 0;
        
        case(state)
            IDLE: begin
                if(start_compute) begin 
                    state <= LOAD_INPUT; 
                    load_cnt <= 0; 
                end
            end
            
            LOAD_INPUT: begin
                lsu_read_req <= 1;
                lsu_read_addr <= input_base + load_cnt;
                if(lsu_read_ready) begin
                    input_buffer[load_cnt >> 2][(load_cnt & 3) * 8 +: 8] <= lsu_read_data;
                    if(load_cnt == 31) begin
                        state <= SETUP_SA;
                    end else begin
                        load_cnt <= load_cnt + 1;
                    end
                end
            end
            
            SETUP_SA: begin
                // 注意：这里目前仍是硬编码测试值，后续需要改为从 input_buffer 读取
                sa_north[0] <= 32'd1; sa_north[1] <= 32'd2; 
                sa_north[2] <= 32'd3; sa_north[3] <= 32'd4;
                sa_west[0] <= 32'd10; sa_west[1] <= 32'd20; 
                sa_west[2] <= 32'd30; sa_west[3] <= 32'd40;
                state <= COMPUTE; compute_cnt <= 0;
            end
            
            COMPUTE: begin
                sa_enable <= 1;
                compute_cnt <= compute_cnt + 1;
                if(compute_cnt == 3 * SA_SIZE - 1) begin 
                    state <= WAIT_RESULT; 
                end
            end
            
            WAIT_RESULT: begin
                if(compute_cnt == 3 * SA_SIZE + 15)
                    state <= READ_RESULT;
                else
                    compute_cnt <= compute_cnt + 1;		
            end
            
            READ_RESULT: begin
                res_byte_idx <= 0;
                res_idx <= 0;
                // 【修改】：读取低 64 位 (即 result[0][0])
                //current_result <= sa_result_flat[63:0];
                current_result <= sa_result_flat[0];
                state <= STORE_OUTPUT;
                $display("RESULT[%d]=%h",res_idx,sa_result_flat[res_idx]);				    
            end
            
            STORE_OUTPUT: begin
                $display("TIME=%0t current_result=%h res_byte=%d",
                    $time,
                    current_result,
                    res_byte_idx);
                lsu_write_req <= 1;
                lsu_write_addr <= output_base + (res_idx * 8) + res_byte_idx;
                lsu_write_data <= current_result[res_byte_idx * 8 +: 8];
                if(lsu_write_ready) begin
                    if(res_byte_idx == 7) begin
                        res_byte_idx <= 0;
                        if(res_idx == 15) begin
                            state <= DONE_STATE;
                        end else begin
                            res_idx <= res_idx + 1;
                            // 【修改】：使用右移操作读取下一个 64 位结果
                            // 例如 res_idx=1 时，右移 64 位，低 64 位就是 result[0][1]
                            //current_result <= sa_result_flat >> (res_idx * 64);
                            current_result <= sa_result_flat[res_idx+1];
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
