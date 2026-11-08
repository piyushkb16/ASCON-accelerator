// One-round-per-clock p[8]/p[12] engine. This is a permutation component,
// not a complete AEAD accelerator. See docs/architecture.md for timing.
`timescale 1ns/1ps
`default_nettype none
module ascon_permutation (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    input  wire         p8_i,
    input  wire [319:0] state_i,
    output wire         ready_o,
    output reg          busy_o,
    output reg          done_o,
    output reg  [319:0] state_o
);
    reg  [319:0] state_q;
    reg  [3:0]   round_q;
    wire [319:0] next_state;
    wire [7:0]   round_constant;

    // Index 0 -> f0, ..., index 11 -> 4b. p[8] begins at index 4.
    assign round_constant = {4'hf - round_q, round_q};
    assign ready_o = ~busy_o;

    ascon_round round_datapath (
        .state_i(state_q),
        .round_constant_i(round_constant),
        .state_o(next_state)
    );

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= 320'b0;
            round_q <= 4'b0;
            state_o <= 320'b0;
            busy_o  <= 1'b0;
            done_o  <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (busy_o) begin
                state_q <= next_state;
                if (round_q == 4'd11) begin
                    state_o <= next_state;
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                end else begin
                    round_q <= round_q + 4'd1;
                end
            end else if (start_i) begin
                state_q <= state_i;
                round_q <= p8_i ? 4'd4 : 4'd0;
                busy_o  <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
