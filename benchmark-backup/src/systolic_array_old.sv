`default_nettype none
`timescale 1ns/1ns

module systolic_array #(
    parameter SIZE = 4
)(
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [31:0] north [0:SIZE-1],
    input wire [31:0] west  [0:SIZE-1],
    // 【修改】：使用 1024 位 packed array，sv2v 和 iverilog 兼容性最好
    //output wire [1023:0] result_flat
    output wire [63:0] result_flat [0:SIZE*SIZE-1]
);
    // 内部二维结果和互联线
    wire [63:0] result [0:SIZE-1][0:SIZE-1];
    wire [31:0] south [0:SIZE-1][0:SIZE-1];
    wire [31:0] east  [0:SIZE-1][0:SIZE-1];
    
    genvar i, j;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : ROW
            for (j = 0; j < SIZE; j = j + 1) begin : COL
                wire [31:0] pe_north_in;
                wire [31:0] pe_west_in;
                
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
                
                // 【修改】：使用 localparam 计算常量索引，然后用标准位选择赋值
                // 这样 iverilog 能完美解析，不会出现悬空 x
                localparam idx = i * SIZE + j;
                //assign result_flat[(idx+1)*64-1 : idx*64] = result[i][j];
                assign result_flat[idx] = result[i][j];
            end
        end
    endgenerate
endmodule
`default_nettype wire
