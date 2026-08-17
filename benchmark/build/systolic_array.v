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