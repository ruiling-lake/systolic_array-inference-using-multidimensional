`default_nettype none
`timescale 1ns/1ns

module systolic_test_top #(
    parameter SA_SIZE    = 32,
    parameter ADDR_WIDTH = 16
)(
    input wire clk,
    input wire reset,
    input wire start_compute,
    output wire done,
    input wire [ADDR_WIDTH-1:0] input_base,
    input wire [ADDR_WIDTH-1:0] output_base,

    output wire lsu_read_req,
    output wire [ADDR_WIDTH-1:0] lsu_read_addr,
    input wire [7:0] lsu_read_data,
    input wire lsu_read_ready,

    output wire lsu_write_req,
    output wire [ADDR_WIDTH-1:0] lsu_write_addr,
    output wire [7:0] lsu_write_data,
    input wire lsu_write_ready
);
    initial begin
        $dumpfile("build/systolic_test.vcd");
        // 【优化】：只 dump 顶层接口，不 dump 内部 1024 个 PE，大幅提升仿真速度！
        $dumpvars(1, systolic_test_top);
    end

    wire [31:0] sa_north [0:SA_SIZE-1];
    wire [31:0] sa_west  [0:SA_SIZE-1];
    wire sa_enable;
    wire [63:0] sa_result_flat [0:SA_SIZE*SA_SIZE-1];

    systolic_adapter #(
        .SA_SIZE(SA_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_adapter (
        .clk(clk), .reset(reset),
        .start_compute(start_compute), .done(done),
        .input_base(input_base), .output_base(output_base),
        .lsu_read_req(lsu_read_req), .lsu_read_addr(lsu_read_addr),
        .lsu_read_ready(lsu_read_ready), .lsu_read_data(lsu_read_data),
        .lsu_write_req(lsu_write_req), .lsu_write_addr(lsu_write_addr),
        .lsu_write_data(lsu_write_data), .lsu_write_ready(lsu_write_ready),
        .sa_north(sa_north), .sa_west(sa_west),
        .sa_enable(sa_enable), .sa_result_flat(sa_result_flat)
    );

    systolic_array #(
        .SIZE(SA_SIZE)
    ) u_array (
        .clk(clk), .reset(reset), .enable(sa_enable),
        .north(sa_north), .west(sa_west),
        .result_flat(sa_result_flat)
    );

endmodule
`default_nettype wire
