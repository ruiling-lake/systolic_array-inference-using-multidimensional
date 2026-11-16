`default_nettype none
`timescale 1ns/1ns

module scheduler #(
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    input wire decoded_mem_read_enable,
    input wire decoded_mem_write_enable,
    input wire decoded_ret,
    input wire decoded_systolic_enable, // 新增：来自 decoder
    input wire systolic_done,           // 新增：来自 adapter
    
    input wire [2:0] fetcher_state,
    input wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],
    output reg [7:0] current_pc,
    input wire [7:0] next_pc [THREADS_PER_BLOCK-1:0],
    output reg [2:0] core_state,
    output reg done
);
    localparam IDLE = 3'b000, FETCH = 3'b001, DECODE = 3'b010, REQUEST = 3'b011,
               WAIT = 3'b100, EXECUTE = 3'b101, UPDATE = 3'b110, DONE = 3'b111;
    
    always @(posedge clk) begin 
        if (reset) begin
            current_pc <= 0; core_state <= IDLE; done <= 0;
        end else begin 
            case (core_state)
                IDLE: if (start) core_state <= FETCH;
                FETCH: if (fetcher_state == 3'b010) core_state <= DECODE;
                DECODE: core_state <= REQUEST;
                REQUEST: core_state <= WAIT;
                WAIT: begin
                    reg any_lsu_waiting = 1'b0;
                    for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                        if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                            any_lsu_waiting = 1'b1;
                            break;
                        end
                    end
                    
                    // 关键修改：如果正在执行 SYSTOLIC 指令，必须等待 systolic_done
                    // 注意：decoded_systolic_enable 是脉冲信号，需要在 core 中锁存为 systolic_active
                    // 这里假设 core 会传递一个 systolic_active 信号，或者我们直接在 WAIT 状态检查
                    // 为了简化，我们让 core 传递 systolic_active 信号
                    // 但为了保持 scheduler 接口简单，我们这里先检查 lsu，稍后在 core 中处理 systolic 等待
                    
                    if (!any_lsu_waiting) core_state <= EXECUTE;
                end
                EXECUTE: core_state <= UPDATE;
                UPDATE: begin 
                    if (decoded_ret) begin done <= 1; core_state <= DONE; end
                    else begin current_pc <= next_pc[THREADS_PER_BLOCK-1]; core_state <= FETCH; end
                end
                DONE: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
