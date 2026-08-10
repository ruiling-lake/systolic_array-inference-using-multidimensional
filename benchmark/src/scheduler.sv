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
    input wire decoded_systolic_enable, // 来自 decoder
    input wire systolic_done,           // 来自 adapter
    input wire systolic_active,         // 来自 core 的脉动阵列激活信号
    input wire [2:0] fetcher_state,
    input wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],
    output reg [7:0] current_pc,
    input wire [7:0] next_pc [THREADS_PER_BLOCK-1:0],
    output reg [2:0] core_state,
    output reg done
);
    localparam IDLE = 3'b000, FETCH = 3'b001, DECODE = 3'b010, REQUEST = 3'b011,
               WAIT = 3'b100, EXECUTE = 3'b101, UPDATE = 3'b110, DONE = 3'b111;
    
    // 【修复 sv2v 兼容性】：将变量声明移到 always 块外部
    reg any_lsu_waiting;
    integer i;
    
    always @(posedge clk) begin 
        if (reset) begin
            current_pc <= 0; 
            core_state <= IDLE; 
            done <= 0;
        end else begin 
            case (core_state)
                IDLE: begin
                    if (start) core_state <= FETCH;
                end
                FETCH: begin
                    if (fetcher_state == 3'b010) core_state <= DECODE;
                end
                DECODE: begin
                    core_state <= REQUEST;
                end
                REQUEST: begin
                    core_state <= WAIT;
                end
                WAIT: begin
                    any_lsu_waiting = 1'b0;
                    for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                        if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                            any_lsu_waiting = 1'b1;
                        end
                    end
                    
                    // 【核心修复】：必须等待 LSU 和 Systolic 都完成才能进入 EXECUTE
                    if (!any_lsu_waiting && !systolic_active) begin
                        core_state <= EXECUTE;
                    end else if (systolic_active && systolic_done) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    core_state <= UPDATE;
                end
                UPDATE: begin 
                    if (decoded_ret) begin 
                        done <= 1; 
                        core_state <= DONE; 
                    end else begin 
                        current_pc <= next_pc[THREADS_PER_BLOCK-1]; 
                        core_state <= FETCH; 
                    end
                end
                DONE: begin
                    // 保持在 DONE 状态，直到外部 reset
                end
                default: begin
                    core_state <= IDLE;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
