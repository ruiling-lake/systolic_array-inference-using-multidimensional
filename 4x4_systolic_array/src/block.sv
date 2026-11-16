`default_nettype none
`timescale 1ns/1ns

module block(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    input  wire [31:0] inp_north,
    input  wire [31:0] inp_west,

    output reg  [31:0] outp_south,
    output reg  [31:0] outp_east,

    // 保持外部接口为 64 位，不影响顶层模块实例化
    output reg  [63:0] result
);

    // 【核心修复】：内部使用 64 位有符号寄存器进行累加
    // 这样 32 位的乘积在相加时，会被正确地“符号扩展”为 64 位，而不是“零扩展”
    reg signed [63:0] acc;

    always @(posedge clk) begin
        if(reset) begin
            outp_south <= 32'd0;
            outp_east  <= 32'd0;
            acc <= 64'sd0;  // 有符号的 0
        end
        else begin
            outp_south <= inp_north;
            outp_east  <= inp_west;

            if(enable) begin
                // 完美的有符号 64 位累加
                acc <= acc + ($signed(inp_north) * $signed(inp_west));
            end
        end
    end

    // 将内部有符号结果按位原样赋值给输出端口（位模式完全一致）
    always @(*) begin
        result = acc;
    end

    // 调试打印：现在打印出来的 result 和 product 都会是正确的有符号十六进制表示
    always @(posedge clk) begin
        if (enable) begin
            $display(
                "%t PE result=%h north=%d west=%d product=%h",
                $time,
                acc,
                $signed(inp_north),
                $signed(inp_west),
                $signed(inp_north) * $signed(inp_west)
            );
        end
    end

endmodule

`default_nettype wire
