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
    output reg  [63:0] result
);

    reg initialized;

    always @(posedge clk) begin
        if (reset) begin
            outp_south  <= 32'd0;
            outp_east   <= 32'd0;
            result      <= 64'd0;
            initialized <= 1'b0;
        end
        else begin
            // 保持原有的直通逻辑 (无论 enable 是否为 1 都更新)
            outp_south <= inp_north;
            outp_east  <= inp_west;

            if (enable) begin
                if (!initialized) begin
                    // 必须将操作数扩展到 64 位再相乘，防止 32 位乘法溢出截断
                    result      <= {32'b0, inp_north} * {32'b0, inp_west};
                    initialized <= 1'b1;
                end
                else begin
                    result <= result + ({32'b0, inp_north} * {32'b0, inp_west});
                end
                
                // 调试打印：已修复缺失的右括号 ")"
                // ⚠️ 注意：由于使用的是非阻塞赋值 (<=)，此处打印的 result 是【更新前】的旧值。
                // 如果希望打印累加后的新值，建议直接打印计算表达式，或在此处临时使用阻塞赋值 (=) 仅用于打印。
                $display("%t block result=%h north=%d west=%d", 
                         $time, result, inp_north, inp_west);
            end
        end
    end

endmodule

`default_nettype wire
