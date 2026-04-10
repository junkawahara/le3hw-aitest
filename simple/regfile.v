// regfile.v - SIMPLE/B レジスタファイル (8 x 16bit)
// 2リード / 1ライトポート, 非同期リード

module regfile(
    input             clk,
    input             rst_n,
    input      [2:0]  rd_addr0,
    input      [2:0]  rd_addr1,
    output     [15:0] rd_data0,
    output     [15:0] rd_data1,
    input             we,
    input      [2:0]  wr_addr,
    input      [15:0] wr_data
);

reg [15:0] regs [0:7];

assign rd_data0 = regs[rd_addr0];
assign rd_data1 = regs[rd_addr1];

integer i;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        for (i = 0; i < 8; i = i + 1)
            regs[i] <= 16'h0000;
    end else if (we) begin
        regs[wr_addr] <= wr_data;
    end
end

endmodule
