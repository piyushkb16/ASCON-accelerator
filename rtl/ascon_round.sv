// Conventional ASCON round: constant addition, 64 parallel 5-bit S-boxes,
// then per-word linear diffusion. NIST SP 800-232, Section 3.
// Packed state = {x0, x1, x2, x3, x4}; each x is a numeric 64-bit word.
`timescale 1ns/1ps
`default_nettype none
module ascon_round (
    input  wire [319:0] state_i,
    input  wire [7:0]   round_constant_i,
    output wire [319:0] state_o
);
    wire [63:0] x0, x1, x2, x3, x4;
    wire [63:0] a0, a1, a2, a3, a4;
    wire [63:0] b0, b1, b2, b3, b4;
    wire [63:0] s0, s1, s2, s3, s4;
    wire [63:0] y0, y1, y2, y3, y4;

    assign {x0, x1, x2, x3, x4} = state_i;

    // Initial affine layer includes addition of the round constant to x2.
    assign a0 = x0 ^ x4;
    assign a1 = x1;
    assign a2 = x2 ^ {56'b0, round_constant_i} ^ x1;
    assign a3 = x3;
    assign a4 = x4 ^ x3;

    // Compute these simultaneously from the same a values.
    assign b0 = a0 ^ ((~a1) & a2);
    assign b1 = a1 ^ ((~a2) & a3);
    assign b2 = a2 ^ ((~a3) & a4);
    assign b3 = a3 ^ ((~a4) & a0);
    assign b4 = a4 ^ ((~a0) & a1);

    assign s0 = b0 ^ b4;
    assign s1 = b1 ^ b0;
    assign s2 = ~b2;
    assign s3 = b3 ^ b2;
    assign s4 = b4;

    // Constant rotations are wiring, not variable barrel shifters.
    assign y0 = s0 ^ {s0[18:0], s0[63:19]} ^ {s0[27:0], s0[63:28]};
    assign y1 = s1 ^ {s1[60:0], s1[63:61]} ^ {s1[38:0], s1[63:39]};
    assign y2 = s2 ^ {s2[0],    s2[63:1]}  ^ {s2[5:0],  s2[63:6]};
    assign y3 = s3 ^ {s3[9:0],  s3[63:10]} ^ {s3[16:0], s3[63:17]};
    assign y4 = s4 ^ {s4[6:0],  s4[63:7]}  ^ {s4[40:0], s4[63:41]};

    assign state_o = {y0, y1, y2, y3, y4};
endmodule
`default_nettype wire
