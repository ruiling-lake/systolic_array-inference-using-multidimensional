`default_nettype none
`timescale 1ns/1ns

module lsu (
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [2:0] core_state,
    input wire decoded_mem_read_enable,
    input wire decoded_mem_write_enable,
    input wire [7:0] rs,
    input wire [7:0] rt,

    output reg mem_read_valid,
    output reg [7:0] mem_read_address,
    input wire mem_read_ready,
    input wire [7:0] mem_read_data,
    output reg mem_write_valid,
    output reg [7:0] mem_write_address,
    output reg [7:0] mem_write_data,
    input wire mem_write_ready,

    output reg [1:0] lsu_state,
    output reg [7:0] lsu_out
);
    localparam IDLE = 2'b00, REQUESTING = 2'b01, WAITING = 2'b10, DONE = 2'b11;

    always @(posedge clk) begin
        if (reset) begin
            lsu_state <= IDLE; lsu_out <= 0; mem_read_valid <= 0; mem_read_address <= 0;
            mem_write_valid <= 0; mem_write_address <= 0; mem_write_data <= 0;
        end else if (enable) begin
            if (decoded_mem_read_enable && lsu_state == IDLE && core_state == 3'b011) lsu_state <= REQUESTING;
            if (decoded_mem_write_enable && lsu_state == IDLE && core_state == 3'b011) lsu_state <= REQUESTING;

            case (lsu_state)
                REQUESTING: begin 
                    if (decoded_mem_read_enable) begin mem_read_valid <= 1; mem_read_address <= rs; end
                    else if (decoded_mem_write_enable) begin mem_write_valid <= 1; mem_write_address <= rs; mem_write_data <= rt; end
                    lsu_state <= WAITING;
                end
                WAITING: begin
                    if (decoded_mem_read_enable && mem_read_ready) begin mem_read_valid <= 0; lsu_out <= mem_read_data; lsu_state <= DONE; end
                    else if (decoded_mem_write_enable && mem_write_ready) begin mem_write_valid <= 0; lsu_state <= DONE; end
                end
                DONE: begin if (core_state == 3'b110) lsu_state <= IDLE; end
                default: lsu_state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
