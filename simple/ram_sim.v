// ram_sim.v - ram.v (altsyncram) のシミュレーション用動作モデル
// Quartus生成の ram.v と同じインタフェース
// 同期アドレスラッチ + UNREGISTERED出力 (組み合わせ読み出し)

module ram(
    input  [11:0] address,
    input         clock,
    input  [15:0] data,
    input         wren,
    output [15:0] q
);

parameter INIT_FILE = "test.hex";

reg [15:0] mem [0:4095];
reg [11:0] addr_reg;

initial begin
    $readmemh(INIT_FILE, mem);
    addr_reg = 12'd0;
end

always @(posedge clock) begin
    addr_reg <= address;
    if (wren)
        mem[address] <= data;
end

assign q = mem[addr_reg];

endmodule
