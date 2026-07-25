`default_nettype none
`timescale 1ns/1ns

module systolic_test_top #(
    parameter SA_SIZE = 4
)(
    input wire clk,
    input wire reset,
    input wire start_compute,
    output wire done,
    input wire [7:0] input_base,
    input wire [7:0] output_base,
    
    output wire lsu_read_req,
    output wire [7:0] lsu_read_addr,
    input wire [7:0] lsu_read_data,
    input wire lsu_read_ready,
    
    output wire lsu_write_req,
    output wire [7:0] lsu_write_addr,
    output wire [7:0] lsu_write_data,
    input wire lsu_write_ready
);
    initial begin
        $dumpfile("build/systolic_test.vcd");
        $dumpvars(0, systolic_test_top);
    end

    // 【修改】：删除数组端口，改为单数据流端口
    wire [31:0] sa_north_in;
    wire [31:0] sa_west_in;
    wire sa_enable;
    wire [63:0] sa_result_flat [0:SA_SIZE*SA_SIZE-1];

    systolic_adapter #(
        .SA_SIZE(SA_SIZE)
    ) u_adapter (
        .clk(clk), .reset(reset), .start_compute(start_compute), .done(done),
        .input_base(input_base), .output_base(output_base),
        .lsu_read_req(lsu_read_req), .lsu_read_addr(lsu_read_addr),
        .lsu_read_ready(lsu_read_ready), .lsu_read_data(lsu_read_data),
        .lsu_write_req(lsu_write_req), .lsu_write_addr(lsu_write_addr),
        .lsu_write_data(lsu_write_data), .lsu_write_ready(lsu_write_ready),
        
        // 【修改】：连接到新的单数据流端口
        .sa_north_in(sa_north_in), 
        .sa_west_in(sa_west_in), 
        .sa_enable(sa_enable),
        .sa_result_flat(sa_result_flat)
    );

    systolic_array #(
        .SIZE(SA_SIZE)
    ) u_array (
        .clk(clk), .reset(reset), .enable(sa_enable),
        // 【修改】：连接到新的单数据流端口
        .north_in(sa_north_in), 
        .west_in(sa_west_in), 
        .result_flat(sa_result_flat)
    );

endmodule
`default_nettype wire
