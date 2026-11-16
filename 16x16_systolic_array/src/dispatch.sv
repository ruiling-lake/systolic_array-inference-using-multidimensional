`default_nettype none
`timescale 1ns/1ns

module dispatch #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [7:0] thread_count,
    input wire [NUM_CORES-1:0] core_done,
    
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],
    output reg done
);
    reg [7:0] current_block_id;
    reg [7:0] active_cores;
    reg [7:0] finished_cores;

    always @(posedge clk) begin
        if (reset) begin
            core_start <= 0; core_reset <= 0; current_block_id <= 0;
            active_cores <= 0; finished_cores <= 0; done <= 0;
            for (int i = 0; i < NUM_CORES; i = i + 1) begin
                core_block_id[i] <= 0; core_thread_count[i] <= 0;
            end
        end else begin
            if (start && active_cores == 0) begin
                current_block_id <= current_block_id + 1; active_cores <= NUM_CORES;
                finished_cores <= 0; done <= 0;
                for (int i = 0; i < NUM_CORES; i = i + 1) begin
                    core_start[i] <= 1; core_reset[i] <= 0;
                    core_block_id[i] <= current_block_id; core_thread_count[i] <= thread_count;
                end
            end else begin
                core_start <= 0;
                for (int i = 0; i < NUM_CORES; i = i + 1) begin
                    if (core_done[i] && !(finished_cores & (1 << i))) finished_cores <= finished_cores | (1 << i);
                end
                if (active_cores > 0 && finished_cores == active_cores) begin
                    done <= 1; active_cores <= 0; finished_cores <= 0;
                end
            end
        end
    end
endmodule
`default_nettype wire
