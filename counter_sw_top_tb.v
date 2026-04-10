// counter_sw_top_tb.v - 課題3 テストベンチ
// カウンタ動作 + スイッチ停止/再開 + チャタリング除去の検証

`timescale 1ns / 1ps

module counter_sw_top_tb;

reg        clk;
reg        rst_n;
reg        sw;
wire [7:0] seg;
wire [7:0] sel;

// シミュレーション用に分周比を小さくする
counter_sw_top #(
    .COUNT_DIV(20),
    .DISP_DIV(5),
    .DB_TIME(10)
) uut (
    .clk(clk),
    .rst_n(rst_n),
    .sw(sw),
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
    sw    = 1'b1; // スイッチ未押下

    // リセット
    #35;
    rst_n = 1'b0;
    #100;
    rst_n = 1'b1;

    // カウント動作確認 (数カウント分待機)
    #5000;

    // スイッチ押下 (停止)
    $display("Time %0t: Switch pressed (stop)", $time);
    sw = 1'b0;
    #1000;
    sw = 1'b1;

    // 停止中の確認
    #5000;

    // スイッチ押下 (再開)
    $display("Time %0t: Switch pressed (resume)", $time);
    sw = 1'b0;
    #1000;
    sw = 1'b1;

    // 再開後の動作確認
    #5000;

    // チャタリングのシミュレーション
    $display("Time %0t: Switch with chattering", $time);
    sw = 1'b0; #50;
    sw = 1'b1; #30;  // チャタリング
    sw = 1'b0; #40;  // チャタリング
    sw = 1'b1; #20;  // チャタリング
    sw = 1'b0;       // 最終的に押下状態で安定
    #2000;
    sw = 1'b1;

    #5000;

    $display("Simulation finished.");
    $stop;
end

endmodule
