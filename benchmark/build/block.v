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