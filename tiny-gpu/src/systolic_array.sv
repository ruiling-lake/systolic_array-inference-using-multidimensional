`default_nettype none
`timescale 1ns/1ns

module systolic_array #(
    parameter SIZE = 4
)(
    input wire clk,
    input wire reset,
    input wire enable,

    // 【修改】：改为单数据流输入，符合脉动阵列数据流模型
    input wire [31:0] north_in,
    input wire [31:0] west_in,

    // 输出保持 unpacked array 格式，兼容性最好
    output wire [63:0] result_flat [0:SIZE*SIZE-1]
);

    // 内部二维结果和互联线
    wire [63:0] result [0:SIZE-1][0:SIZE-1];
    wire [31:0] south [0:SIZE-1][0:SIZE-1];
    wire [31:0] east  [0:SIZE-1][0:SIZE-1];
    
    // 【新增】：输入移位寄存器，用于产生斜向数据流
    reg [31:0] north_shift [0:SIZE-1];
    reg [31:0] west_shift  [0:SIZE-1];
    
    integer k;
    always @(posedge clk) begin
        if (reset) begin
            for (k = 0; k < SIZE; k = k + 1) begin
                north_shift[k] <= 32'd0;
                west_shift[k]  <= 32'd0;
            end
        end
        else if (enable) begin
            // 新数据从索引 0 进入，旧数据向高索引移位
            north_shift[0] <= north_in;
            west_shift[0]  <= west_in;
            
            for (k = 1; k < SIZE; k = k + 1) begin
                north_shift[k] <= north_shift[k-1];
                west_shift[k]  <= west_shift[k-1];
            end
        end
    end

    genvar i, j;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : ROW
            for (j = 0; j < SIZE; j = j + 1) begin : COL
                wire [31:0] pe_north_in;
                wire [31:0] pe_west_in;
                
                // 【修改】：第一行/列从移位寄存器获取数据，其余从上游 PE 获取
                assign pe_north_in = (i == 0) ? north_shift[j] : south[i-1][j];
                assign pe_west_in  = (j == 0) ? west_shift[i]  : east[i][j-1];
                
                block u_pe (
                    .clk        (clk),
                    .reset      (reset),
                    .enable     (enable),
                    .inp_north  (pe_north_in),
                    .inp_west   (pe_west_in),
                    .outp_south (south[i][j]),
                    .outp_east  (east[i][j]),
                    .result     (result[i][j])
                );
                
                localparam idx = i * SIZE + j;
                assign result_flat[idx] = result[i][j];
            end
        end
    endgenerate

endmodule

`default_nettype wire
