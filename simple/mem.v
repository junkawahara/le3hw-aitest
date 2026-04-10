// mem.v - SIMPLE/B 主記憶
// 非同期リード / 同期ライト
// $readmemh でプログラムを初期化

module mem(
    input         clk,
    input  [15:0] addr,
    input  [15:0] wdata,
    input         we,
    output [15:0] rdata
);

parameter ADDR_WIDTH = 8;  // 256語 (デフォルト)
parameter INIT_FILE  = "test.hex";

reg [15:0] ram [0:(1 << ADDR_WIDTH) - 1];

initial begin
    $readmemh(INIT_FILE, ram);
end

assign rdata = ram[addr[ADDR_WIDTH-1:0]];

always @(posedge clk) begin
    if (we)
        ram[addr[ADDR_WIDTH-1:0]] <= wdata;
end

endmodule
