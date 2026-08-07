`default_nettype none
`timescale 1ns/1ns

module pc #(
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [2:0] core_state,
    input wire [2:0] decoded_nzp,
    input wire [DATA_MEM_DATA_BITS-1:0] decoded_immediate,
    input wire decoded_nzp_write_enable,
    input wire decoded_pc_mux, 
    input wire [DATA_MEM_DATA_BITS-1:0] alu_out,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);
    reg [2:0] nzp;

    always @(posedge clk) begin
        if (reset) begin
            nzp <= 3'b0; next_pc <= 0;
        end else if (enable) begin
            if (core_state == 3'b101) begin 
                if (decoded_pc_mux == 1) begin 
                    if (((nzp & decoded_nzp) != 3'b0)) begin next_pc <= decoded_immediate; end
                    else begin next_pc <= current_pc + 1; end
                end else begin next_pc <= current_pc + 1; end
            end   
            if (core_state == 3'b110) begin 
                if (decoded_nzp_write_enable) begin
                    nzp[2] <= alu_out[2]; nzp[1] <= alu_out[1]; nzp[0] <= alu_out[0];
                end
            end      
        end
    end
endmodule
`default_nettype wire
