`default_nettype none
`timescale 1ns/1ns

module systolic_array #(
    parameter SIZE = 4
)(
    input wire clk,
    input wire reset,
    input wire enable,

    // 恢复为数组端口，每个周期同时输入一整行和一整列
    input wire [31:0] north [0:SIZE-1],
    input wire [31:0] west  [0:SIZE-1],

    output wire [63:0] result_flat [0:SIZE*SIZE-1]
);

    wire [63:0] result [0:SIZE-1][0:SIZE-1];
    wire [31:0] south [0:SIZE-1][0:SIZE-1];
    wire [31:0] east  [0:SIZE-1][0:SIZE-1];
    
    genvar i, j;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : ROW
            for (j = 0; j < SIZE; j = j + 1) begin : COL
                wire [31:0] pe_north_in;
                wire [31:0] pe_west_in;
                
                // 标准脉动阵列连接：第一行/列从外部数组获取，其余从上游 PE 获取
                assign pe_north_in = (i == 0) ? north[j] : south[i-1][j];
                assign pe_west_in  = (j == 0) ? west[i]  : east[i][j-1];
                
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
