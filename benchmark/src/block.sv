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


always @(posedge clk) begin

    if(reset) begin

        outp_south <= 32'd0;
        outp_east  <= 32'd0;

        result <= 64'd0;

    end

    else begin

        /*
         * 数据继续向下、向右传播
         *
         * north -> south
         * west  -> east
         */
        outp_south <= inp_north;
        outp_east  <= inp_west;


        /*
         * PE累加操作
         *
         * result += A*B
         *
         */
        if(enable) begin

            result <= result +
                      (
                       {32'd0,inp_north}
                       *
                       {32'd0,inp_west}
                      );


            $display(
                "%t PE result=%h north=%d west=%d product=%h",
                $time,
                result,
                inp_north,
                inp_west,
                ({32'd0,inp_north}*
                 {32'd0,inp_west})
            );

        end

    end

end


endmodule


`default_nettype wire
