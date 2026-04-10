// simple_top.v - SIMPLE/B トップモジュール
// CPU + メモリ + 7セグ表示 + I/O
//
// ピンアサイン: ピンアサイン表を参照して設定すること
//   clk      : 20MHz クロック
//   rst_n    : リセットボタン (負論理)
//   exec     : 実行ボタン (正論理: 押すと1)
//   sw[15:0] : DIPスイッチ (IN命令用, 負論理)
//   seg[7:0] : 7セグメントLEDセグメント出力
//   sel[7:0] : 7セグメントLED桁選択

module simple_top(
    input         clk,
    input         rst_n,
    input         exec,
    input  [15:0] sw,
    output [7:0]  seg,
    output [7:0]  sel
);

// ---- CPU ↔ メモリ接続 ----
wire [15:0] mem_addr, mem_rdata, mem_wdata;
wire        mem_we;

// ---- CPU ↔ I/O ----
wire [15:0] cpu_out_data;
wire        cpu_out_we;
wire        cpu_halted;

simple_cpu cpu(
    .clk(clk), .rst_n(rst_n), .exec(exec),
    .mem_addr(mem_addr), .mem_rdata(mem_rdata),
    .mem_wdata(mem_wdata), .mem_we(mem_we),
    .in_data(~sw),  // DIPスイッチ負論理を反転
    .out_data(cpu_out_data), .out_we(cpu_out_we),
    .halted(cpu_halted)
);

// ram.v (altsyncram Block RAM, 4096語, run.mif で初期化)
// シミュレーション時は ram_sim.v を使用
ram memory(
    .clock(clk),
    .address(mem_addr[11:0]),
    .q(mem_rdata),
    .data(mem_wdata),
    .wren(mem_we)
);

// ---- OUT レジスタ ----
reg [15:0] out_reg;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n)
        out_reg <= 16'h0000;
    else if (cpu_out_we)
        out_reg <= cpu_out_data;
end

// ---- 7セグ表示 (out_reg を4桁16進数で表示) ----
parameter DISP_DIV = 5000; // 20MHz / 5000 = 4kHz

reg [12:0] disp_cnt;
wire       disp_en = (disp_cnt == DISP_DIV - 1);

always @(posedge clk or negedge rst_n) begin
    if (~rst_n)      disp_cnt <= 13'd0;
    else if (disp_en) disp_cnt <= 13'd0;
    else             disp_cnt <= disp_cnt + 13'd1;
end

reg [1:0] dig_sel;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n)       dig_sel <= 2'd0;
    else if (disp_en) dig_sel <= dig_sel + 2'd1;
end

wire [3:0] cur_dig = (dig_sel == 2'd0) ? out_reg[3:0]   :
                     (dig_sel == 2'd1) ? out_reg[7:4]   :
                     (dig_sel == 2'd2) ? out_reg[11:8]  :
                                         out_reg[15:12] ;

seg7dec dec(.din(cur_dig), .seg(seg));

assign sel = (dig_sel == 2'd0) ? 8'b11111110 :
             (dig_sel == 2'd1) ? 8'b11111101 :
             (dig_sel == 2'd2) ? 8'b11111011 :
                                 8'b11110111 ;

endmodule
