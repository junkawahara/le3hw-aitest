// alu.v - SIMPLE/B ALU
// ADD, SUB, AND, OR, XOR, CMP, MOV + アドレス計算(ADD流用)

module alu(
    input  [15:0] a,
    input  [15:0] b,
    input  [3:0]  op,
    output [15:0] result,
    output        flag_s,
    output        flag_z,
    output        flag_c,
    output        flag_v
);

wire [16:0] sum  = {1'b0, a} + {1'b0, b};
wire [16:0] diff = {1'b0, a} + {1'b0, ~b} + 17'd1;

assign result = (op == 4'h0) ? sum[15:0]  :  // ADD
                (op == 4'h1) ? diff[15:0]  :  // SUB
                (op == 4'h2) ? (a & b)     :  // AND
                (op == 4'h3) ? (a | b)     :  // OR
                (op == 4'h4) ? (a ^ b)     :  // XOR
                (op == 4'h5) ? diff[15:0]  :  // CMP (= SUB)
                (op == 4'h6) ? b           :  // MOV
                               16'h0000;

assign flag_s = result[15];
assign flag_z = (result == 16'h0000);

assign flag_c = (op == 4'h0)                ? sum[16]  :
                (op == 4'h1 || op == 4'h5)  ? diff[16] :
                                              1'b0;

wire add_ov = (~a[15] & ~b[15] & result[15]) | (a[15] & b[15] & ~result[15]);
wire sub_ov = (~a[15] &  b[15] & result[15]) | (a[15] & ~b[15] & ~result[15]);

assign flag_v = (op == 4'h0)                ? add_ov :
                (op == 4'h1 || op == 4'h5)  ? sub_ov :
                                              1'b0;

endmodule
