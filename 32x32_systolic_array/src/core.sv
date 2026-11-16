`default_nettype none
`timescale 1ns/1ns

module core #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter THREADS_PER_BLOCK = 4,
    parameter SA_SIZE = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,
    input wire [7:0] block_id,
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    output reg program_mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input wire program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    output reg [THREADS_PER_BLOCK-1:0] data_mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [THREADS_PER_BLOCK-1:0],
    input wire [THREADS_PER_BLOCK-1:0] data_mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [THREADS_PER_BLOCK-1:0],
    
    output reg [THREADS_PER_BLOCK-1:0] data_mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_BLOCK-1:0],
    output reg [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [THREADS_PER_BLOCK-1:0],
    input wire [THREADS_PER_BLOCK-1:0] data_mem_write_ready,
    
    output wire systolic_done
);

    reg [2:0] core_state, fetcher_state;
    reg [15:0] instruction;
    reg [7:0] current_pc;
    wire [7:0] next_pc[THREADS_PER_BLOCK-1:0];
    reg [7:0] rs[THREADS_PER_BLOCK-1:0], rt[THREADS_PER_BLOCK-1:0];
    reg [1:0] lsu_state[THREADS_PER_BLOCK-1:0];
    reg [7:0] lsu_out[THREADS_PER_BLOCK-1:0];
    wire [7:0] alu_out[THREADS_PER_BLOCK-1:0];
    
    reg [3:0] decoded_rd_address, decoded_rs_address, decoded_rt_address;
    reg [2:0] decoded_nzp;
    reg [7:0] decoded_immediate;
    reg decoded_reg_write_enable, decoded_mem_read_enable, decoded_mem_write_enable;
    reg decoded_nzp_write_enable;
    reg [1:0] decoded_reg_input_mux, decoded_alu_arithmetic_mux;
    reg decoded_alu_output_mux, decoded_pc_mux, decoded_ret, decoded_systolic_enable;
    
    // 新增：SYSTOLIC 指令控制信号
    reg systolic_active;
    reg [7:0] systolic_input_base, systolic_output_base;
    reg systolic_start_pulse;
    
     wire systolic_start;
    wire [31:0] sa_north [0:SA_SIZE-1];
    wire [31:0] sa_west [0:SA_SIZE-1];
    wire sa_enable;
    
    // 只声明一维展平的结果数组
    wire [63:0] sa_result_flat [0:SA_SIZE*SA_SIZE-1];
    
    wire sa_mem_read_valid, sa_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] sa_mem_read_address, sa_mem_write_address;
    wire [DATA_MEM_DATA_BITS-1:0] sa_mem_write_data;
    wire sa_mem_read_ready, sa_mem_write_ready;
    wire [DATA_MEM_DATA_BITS-1:0] sa_mem_read_data;

    fetcher #(.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS), .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)) fetcher_instance (
        .clk(clk), .reset(reset), .core_state(core_state), .current_pc(current_pc),
        .mem_read_valid(program_mem_read_valid), .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready), .mem_read_data(program_mem_read_data),
        .fetcher_state(fetcher_state), .instruction(instruction) 
    );

    decoder decoder_instance (
        .clk(clk), .reset(reset), .core_state(core_state), .instruction(instruction),
        .decoded_rd_address(decoded_rd_address), .decoded_rs_address(decoded_rs_address),
        .decoded_rt_address(decoded_rt_address), .decoded_nzp(decoded_nzp), .decoded_immediate(decoded_immediate),
        .decoded_reg_write_enable(decoded_reg_write_enable), .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable), .decoded_nzp_write_enable(decoded_nzp_write_enable),
        .decoded_reg_input_mux(decoded_reg_input_mux), .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
        .decoded_alu_output_mux(decoded_alu_output_mux), .decoded_pc_mux(decoded_pc_mux),
        .decoded_ret(decoded_ret), .decoded_systolic_enable(decoded_systolic_enable)
    );

    scheduler #(.THREADS_PER_BLOCK(THREADS_PER_BLOCK)) scheduler_instance (
        .clk(clk), .reset(reset), .start(start), .fetcher_state(fetcher_state), .core_state(core_state),
        .decoded_mem_read_enable(decoded_mem_read_enable), .decoded_mem_write_enable(decoded_mem_write_enable),
        .decoded_ret(decoded_ret), .lsu_state(lsu_state), .current_pc(current_pc), .next_pc(next_pc), .done(done),
        .decoded_systolic_enable(decoded_systolic_enable), // 【补全】
        .systolic_done(systolic_done), .systolic_active(systolic_active) // 【新增】：连接脉动阵列激活信号
    );

    // SYSTOLIC 指令状态机
    always @(posedge clk) begin
        if (reset) begin
            systolic_active <= 0;
            systolic_start_pulse <= 0;
        end else begin
            // 在 DECODE 状态激活 SYSTOLIC
            if (core_state == 3'b010 && decoded_systolic_enable) begin
                systolic_active <= 1;
            end
            
            // 在 REQUEST 状态读取基地址并触发 adapter
            if (core_state == 3'b011 && systolic_active) begin
                systolic_input_base <= rs[0]; // 假设 rs[0] 存放 input_base
                systolic_output_base <= rt[0]; // 假设 rt[0] 存放 output_base
                systolic_start_pulse <= 1;
            end else begin
                systolic_start_pulse <= 0;
            end
            
            // 在 UPDATE 状态清除
            if (core_state == 3'b110) begin
                systolic_active <= 0;
            end
        end
    end
    
    assign systolic_start = systolic_start_pulse;

    
    // systolic_array 只连接 result_flat
    systolic_array #(.SIZE(SA_SIZE)) u_systolic_array (
        .clk(clk), 
        .reset(reset), 
        .enable(sa_enable), 
        .north(sa_north), 
        .west(sa_west), 
        .result_flat(sa_result_flat) // 正确连接一维展平结果
    );

    // systolic_adapter 接收正确的一维展平结果
    systolic_adapter #(.SA_SIZE(SA_SIZE)) u_systolic_adapter (
        .clk(clk), .reset(reset), .start_compute(systolic_start), .done(systolic_done),
        .input_base(systolic_input_base), .output_base(systolic_output_base),
        .lsu_read_req(sa_mem_read_valid), .lsu_read_addr(sa_mem_read_address),
        .lsu_read_ready(sa_mem_read_ready), .lsu_read_data(sa_mem_read_data),
        .lsu_write_req(sa_mem_write_valid), .lsu_write_addr(sa_mem_write_address),
        .lsu_write_data(sa_mem_write_data), .lsu_write_ready(sa_mem_write_ready),
        .sa_north(sa_north), .sa_west(sa_west), .sa_enable(sa_enable), 
        .sa_result_flat(sa_result_flat) // 正确接收一维展平结果
    );

    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads
            alu alu_instance (.clk(clk), .reset(reset), .enable(i < thread_count), .core_state(core_state),
                .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux), .decoded_alu_output_mux(decoded_alu_output_mux),
                .rs(rs[i]), .rt(rt[i]), .alu_out(alu_out[i]));

            lsu lsu_instance (.clk(clk), .reset(reset), .enable(i < thread_count), .core_state(core_state),
                .decoded_mem_read_enable(decoded_mem_read_enable), .decoded_mem_write_enable(decoded_mem_write_enable),
                .mem_read_valid(data_mem_read_valid[i]), .mem_read_address(data_mem_read_address[i]),
                .mem_read_ready(data_mem_read_ready[i]), .mem_read_data(data_mem_read_data[i]),
                .mem_write_valid(data_mem_write_valid[i]), .mem_write_address(data_mem_write_address[i]),
                .mem_write_data(data_mem_write_data[i]), .mem_write_ready(data_mem_write_ready[i]),
                .rs(rs[i]), .rt(rt[i]), .lsu_state(lsu_state[i]), .lsu_out(lsu_out[i]));

            registers #(.THREADS_PER_BLOCK(THREADS_PER_BLOCK), .THREAD_ID(i), .DATA_BITS(DATA_MEM_DATA_BITS)) register_instance (
                .clk(clk), .reset(reset), .enable(i < thread_count), .block_id(block_id), .core_state(core_state),
                .decoded_reg_write_enable(decoded_reg_write_enable), .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_rd_address(decoded_rd_address), .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address), .decoded_immediate(decoded_immediate),
                .alu_out(alu_out[i]), .lsu_out(lsu_out[i]), .rs(rs[i]), .rt(rt[i]));

            pc #(.DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS), .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)) pc_instance (
                .clk(clk), .reset(reset), .enable(i < thread_count), .core_state(core_state),
                .decoded_nzp(decoded_nzp), .decoded_immediate(decoded_immediate),
                .decoded_nzp_write_enable(decoded_nzp_write_enable), .decoded_pc_mux(decoded_pc_mux),
                .alu_out(alu_out[i]), .current_pc(current_pc), .next_pc(next_pc[i]));
        end
    endgenerate

    // 仲裁逻辑（保持原样）
    assign sa_mem_read_ready = sa_mem_read_valid && !data_mem_read_valid[0];
    assign data_mem_read_ready[0] = data_mem_read_valid[0] && !sa_mem_read_valid;
    assign sa_mem_write_ready = sa_mem_write_valid && !data_mem_write_valid[0];
    assign data_mem_write_ready[0] = data_mem_write_valid[0] && !sa_mem_write_valid;
    assign sa_mem_read_data = sa_mem_read_valid ? data_mem_read_data[0] : 8'b0;

    genvar j;
    generate
        for (j = 1; j < THREADS_PER_BLOCK; j = j + 1) begin 
            assign data_mem_read_ready[j] = data_mem_read_valid[j];
            assign data_mem_write_ready[j] = data_mem_write_valid[j];
        end
    endgenerate

endmodule
`default_nettype wire