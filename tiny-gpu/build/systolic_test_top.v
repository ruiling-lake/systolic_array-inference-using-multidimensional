`timescale 1ns/1ns
`default_nettype none
module systolic_test_top (
	clk,
	reset,
	start_compute,
	done,
	input_base,
	output_base,
	lsu_read_req,
	lsu_read_addr,
	lsu_read_data,
	lsu_read_ready,
	lsu_write_req,
	lsu_write_addr,
	lsu_write_data,
	lsu_write_ready
);
	parameter SA_SIZE = 4;
	input wire clk;
	input wire reset;
	input wire start_compute;
	output wire done;
	input wire [7:0] input_base;
	input wire [7:0] output_base;
	output wire lsu_read_req;
	output wire [7:0] lsu_read_addr;
	input wire [7:0] lsu_read_data;
	input wire lsu_read_ready;
	output wire lsu_write_req;
	output wire [7:0] lsu_write_addr;
	output wire [7:0] lsu_write_data;
	input wire lsu_write_ready;
	initial begin
		$dumpfile("build/systolic_test.vcd");
		$dumpvars(0, systolic_test_top);
	end
	wire [(SA_SIZE * 32) - 1:0] sa_north;
	wire [(SA_SIZE * 32) - 1:0] sa_west;
	wire sa_enable;
	wire [((SA_SIZE * SA_SIZE) * 64) - 1:0] sa_result_flat;
	systolic_adapter #(.SA_SIZE(SA_SIZE)) u_adapter(
		.clk(clk),
		.reset(reset),
		.start_compute(start_compute),
		.done(done),
		.input_base(input_base),
		.output_base(output_base),
		.lsu_read_req(lsu_read_req),
		.lsu_read_addr(lsu_read_addr),
		.lsu_read_ready(lsu_read_ready),
		.lsu_read_data(lsu_read_data),
		.lsu_write_req(lsu_write_req),
		.lsu_write_addr(lsu_write_addr),
		.lsu_write_data(lsu_write_data),
		.lsu_write_ready(lsu_write_ready),
		.sa_north(sa_north),
		.sa_west(sa_west),
		.sa_enable(sa_enable),
		.sa_result_flat(sa_result_flat)
	);
	systolic_array #(.SIZE(SA_SIZE)) u_array(
		.clk(clk),
		.reset(reset),
		.enable(sa_enable),
		.north(sa_north),
		.west(sa_west),
		.result_flat(sa_result_flat)
	);
endmodule
`default_nettype wire
`default_nettype none
module systolic_adapter (
	clk,
	reset,
	start_compute,
	done,
	input_base,
	output_base,
	lsu_read_req,
	lsu_read_addr,
	lsu_read_data,
	lsu_read_ready,
	lsu_write_req,
	lsu_write_addr,
	lsu_write_data,
	lsu_write_ready,
	sa_north,
	sa_west,
	sa_enable,
	sa_result_flat
);
	parameter SA_SIZE = 4;
	input wire clk;
	input wire reset;
	input wire start_compute;
	output reg done;
	input wire [7:0] input_base;
	input wire [7:0] output_base;
	output reg lsu_read_req;
	output reg [7:0] lsu_read_addr;
	input wire [7:0] lsu_read_data;
	input wire lsu_read_ready;
	output reg lsu_write_req;
	output reg [7:0] lsu_write_addr;
	output reg [7:0] lsu_write_data;
	input wire lsu_write_ready;
	output reg [(SA_SIZE * 32) - 1:0] sa_north;
	output reg [(SA_SIZE * 32) - 1:0] sa_west;
	output reg sa_enable;
	input wire [((SA_SIZE * SA_SIZE) * 64) - 1:0] sa_result_flat;
	localparam IDLE = 3'd0;
	localparam LOAD_INPUT = 3'd1;
	localparam SETUP_SA = 3'd2;
	localparam COMPUTE = 3'd3;
	localparam WAIT_RESULT = 3'd4;
	localparam READ_RESULT = 3'd5;
	localparam STORE_OUTPUT = 3'd6;
	localparam DONE_STATE = 3'd7;
	reg [2:0] state;
	reg [6:0] load_cnt;
	reg [2:0] res_byte_idx;
	reg [3:0] res_idx;
	reg [5:0] compute_cnt;
	reg [63:0] current_result;
	reg [31:0] input_buffer [0:31];
	reg [31:0] temp_word;
	integer i;
	integer j;
	always @(posedge clk)
		if (reset) begin
			state <= IDLE;
			done <= 0;
			lsu_read_req <= 0;
			lsu_write_req <= 0;
			sa_enable <= 0;
			load_cnt <= 0;
			compute_cnt <= 0;
			res_byte_idx <= 0;
			res_idx <= 0;
			current_result <= 64'd0;
			temp_word <= 32'd0;
			for (i = 0; i < SA_SIZE; i = i + 1)
				begin
					sa_north[((SA_SIZE - 1) - i) * 32+:32] <= 32'd0;
					sa_west[((SA_SIZE - 1) - i) * 32+:32] <= 32'd0;
				end
		end
		else begin
			lsu_read_req <= 0;
			lsu_write_req <= 0;
			sa_enable <= 0;
			done <= 0;
			case (state)
				IDLE:
					if (start_compute) begin
						state <= LOAD_INPUT;
						load_cnt <= 0;
						lsu_read_addr <= input_base;
					end
				LOAD_INPUT: begin
					lsu_read_req <= 1;
					if (lsu_read_ready) begin
						case (load_cnt[1:0])
							2'd0: temp_word[7:0] <= lsu_read_data;
							2'd1: temp_word[15:8] <= lsu_read_data;
							2'd2: temp_word[23:16] <= lsu_read_data;
							2'd3: begin
								temp_word[31:24] <= lsu_read_data;
								input_buffer[load_cnt >> 2] <= {lsu_read_data, temp_word[23:0]};
							end
						endcase
						if (load_cnt == 7'd127)
							state <= SETUP_SA;
						else begin
							load_cnt <= load_cnt + 1'b1;
							lsu_read_addr <= (input_base + load_cnt) + 1'b1;
						end
					end
				end
				SETUP_SA: begin
					state <= COMPUTE;
					compute_cnt <= 0;
				end
				COMPUTE: begin
					sa_enable <= 1;
					for (i = 0; i < SA_SIZE; i = i + 1)
						if ((compute_cnt >= i) && (compute_cnt < (i + SA_SIZE)))
							sa_west[((SA_SIZE - 1) - i) * 32+:32] <= input_buffer[(i * SA_SIZE) + (compute_cnt - i)];
						else
							sa_west[((SA_SIZE - 1) - i) * 32+:32] <= 32'd0;
					for (j = 0; j < SA_SIZE; j = j + 1)
						if ((compute_cnt >= j) && (compute_cnt < (j + SA_SIZE)))
							sa_north[((SA_SIZE - 1) - j) * 32+:32] <= input_buffer[(16 + ((compute_cnt - j) * SA_SIZE)) + j];
						else
							sa_north[((SA_SIZE - 1) - j) * 32+:32] <= 32'd0;
					if (compute_cnt == 6) begin
						state <= WAIT_RESULT;
						compute_cnt <= 0;
					end
					else
						compute_cnt <= compute_cnt + 1;
				end
				WAIT_RESULT: begin
					sa_enable <= 1;
					for (i = 0; i < SA_SIZE; i = i + 1)
						begin
							sa_west[((SA_SIZE - 1) - i) * 32+:32] <= 32'd0;
							sa_north[((SA_SIZE - 1) - i) * 32+:32] <= 32'd0;
						end
					if (compute_cnt == 14)
						state <= READ_RESULT;
					else
						compute_cnt <= compute_cnt + 1;
				end
				READ_RESULT: begin
					res_byte_idx <= 0;
					res_idx <= 0;
					current_result <= sa_result_flat[((SA_SIZE * SA_SIZE) - 1) * 64+:64];
					state <= STORE_OUTPUT;
					$display("RESULT[%0d]=%h", res_idx, sa_result_flat[(((SA_SIZE * SA_SIZE) - 1) - res_idx) * 64+:64]);
				end
				STORE_OUTPUT: begin
					lsu_write_req <= 1;
					lsu_write_addr <= (output_base + (res_idx * 8)) + res_byte_idx;
					lsu_write_data <= current_result[res_byte_idx * 8+:8];
					if (lsu_write_ready) begin
						if (res_byte_idx == 7) begin
							res_byte_idx <= 0;
							if (res_idx == 15)
								state <= DONE_STATE;
							else begin
								res_idx <= res_idx + 1;
								current_result <= sa_result_flat[(((SA_SIZE * SA_SIZE) - 1) - (res_idx + 1)) * 64+:64];
								$display("RESULT[%0d]=%h", res_idx + 1, sa_result_flat[(((SA_SIZE * SA_SIZE) - 1) - (res_idx + 1)) * 64+:64]);
							end
						end
						else
							res_byte_idx <= res_byte_idx + 1;
					end
				end
				DONE_STATE: begin
					done <= 1;
					state <= IDLE;
				end
				default: state <= IDLE;
			endcase
		end
endmodule
`default_nettype wire
`default_nettype none
module systolic_array (
	clk,
	reset,
	enable,
	north,
	west,
	result_flat
);
	parameter SIZE = 4;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [(SIZE * 32) - 1:0] north;
	input wire [(SIZE * 32) - 1:0] west;
	output wire [((SIZE * SIZE) * 64) - 1:0] result_flat;
	wire [63:0] result [0:SIZE - 1][0:SIZE - 1];
	wire [31:0] south [0:SIZE - 1][0:SIZE - 1];
	wire [31:0] east [0:SIZE - 1][0:SIZE - 1];
	genvar _gv_i_1;
	genvar _gv_j_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < SIZE; _gv_i_1 = _gv_i_1 + 1) begin : ROW
			localparam i = _gv_i_1;
			for (_gv_j_1 = 0; _gv_j_1 < SIZE; _gv_j_1 = _gv_j_1 + 1) begin : COL
				localparam j = _gv_j_1;
				wire [31:0] pe_north_in;
				wire [31:0] pe_west_in;
				assign pe_north_in = (i == 0 ? north[((SIZE - 1) - j) * 32+:32] : south[i - 1][j]);
				assign pe_west_in = (j == 0 ? west[((SIZE - 1) - i) * 32+:32] : east[i][j - 1]);
				block u_pe(
					.clk(clk),
					.reset(reset),
					.enable(enable),
					.inp_north(pe_north_in),
					.inp_west(pe_west_in),
					.outp_south(south[i][j]),
					.outp_east(east[i][j]),
					.result(result[i][j])
				);
				localparam idx = (i * SIZE) + j;
				assign result_flat[(((SIZE * SIZE) - 1) - idx) * 64+:64] = result[i][j];
			end
		end
	endgenerate
endmodule
`default_nettype wire
`default_nettype none
module block (
	clk,
	reset,
	enable,
	inp_north,
	inp_west,
	outp_south,
	outp_east,
	result
);
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [31:0] inp_north;
	input wire [31:0] inp_west;
	output reg [31:0] outp_south;
	output reg [31:0] outp_east;
	output reg [63:0] result;
	always @(posedge clk)
		if (reset) begin
			outp_south <= 32'd0;
			outp_east <= 32'd0;
			result <= 64'd0;
		end
		else begin
			outp_south <= inp_north;
			outp_east <= inp_west;
			if (enable) begin
				result <= result + ({32'd0, inp_north} * {32'd0, inp_west});
				$display("%t PE result=%h north=%d west=%d product=%h", $time, result, inp_north, inp_west, {32'd0, inp_north} * {32'd0, inp_west});
			end
		end
endmodule
`default_nettype wire