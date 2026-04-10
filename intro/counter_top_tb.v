// counter_top_tb.v - 課題2 テストベンチ
// 分周パラメータを小さくしてシミュレーション時間を短縮

`timescale 1ns / 1ps

module counter_top_tb;

reg        clk;
reg        rst_n;
wire [7:0] seg;
wire [7:0] sel;

// シミュレーション用に分周比を小さくする
counter_top #(
    .CLK_FREQ(20_000_000),
    .COUNT_DIV(20),    // 20クロックで1カウント (高速化)
    .DISP_DIV(5)       // 5クロックで桁切替 (高速化)
) uut (
    .clk(clk),
    .rst_n(rst_n),
    .seg(seg),
    .sel(sel)
);

// 20MHz クロック生成 (周期50ns)
always begin
    #25 clk = ~clk;
end

initial begin
    clk   = 1'b0;
    rst_n = 1'b1;

    // リセット
    #35;
    rst_n = 1'b0;
    #100;
    rst_n = 1'b1;

    // カウンタが複数回カウントアップするまで待機
    // COUNT_DIV=20, クロック周期50ns → 1カウント = 20*50ns = 1000ns
    // 15カウント分 = 15000ns
    #20000;

    $display("Simulation finished.");
    $stop;
end

endmodule
