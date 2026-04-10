// shifter.v - SIMPLE/B バレルシフタ
// SLL(00), SLR(01), SRL(10), SRA(11)

module shifter(
    input  [15:0] data,
    input  [3:0]  d,
    input  [1:0]  op,
    output reg [15:0] result,
    output reg        flag_c
);

wire [16:0] sll_ext = {1'b0, data} << d;
wire [16:0] srl_ext = {data, 1'b0} >> d;

always @(*) begin
    case (op)
        2'b00: begin // SLL
            result = sll_ext[15:0];
            flag_c = (d == 4'd0) ? 1'b0 : sll_ext[16];
        end
        2'b01: begin // SLR (左循環シフト)
            result = (data << d) | (data >> (5'd16 - {1'b0, d}));
            flag_c = 1'b0;
        end
        2'b10: begin // SRL
            result = data >> d;
            flag_c = (d == 4'd0) ? 1'b0 : srl_ext[0];
        end
        2'b11: begin // SRA
            result = $signed(data) >>> d;
            flag_c = (d == 4'd0) ? 1'b0 : srl_ext[0];
        end
    endcase
end

endmodule
