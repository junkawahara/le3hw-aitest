// counter_top.v - 課題2 トップモジュール
// 10進数4桁カウンタ (ダイナミック点灯)
//
// 20MHzクロック入力で動作
// 約1秒ごとに1カウントアップ (0000→9999→0000...)
// 4桁をダイナミック点灯で表示
//
// ピンアサイン: ピンアサイン表を参照して設定すること
//   clk     : 20MHzクロック入力
//   rst_n   : リセット (負論理)
//   seg[7:0]: 7セグメントLEDセグメント出力
//   sel[7:0]: 7セグメントLED桁選択 (active LOW)

module counter_top(
    input        clk,
    input        rst_n,
    output [7:0] seg,
    output [7:0] sel
);

// パラメータ
parameter CLK_FREQ   = 20_000_000; // 20MHz
parameter COUNT_DIV  = 20_000_000; // 1Hz (1秒ごとにカウント)
parameter DISP_DIV   = 5_000;      // 4kHz (ダイナミック点灯用)

// カウント用分周カウンタ
reg [24:0] cnt_div;
wire       cnt_en;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        cnt_div <= 25'd0;
    end else begin
        if (cnt_div == COUNT_DIV - 1)
            cnt_div <= 25'd0;
        else
            cnt_div <= cnt_div + 25'd1;
    end
end

assign cnt_en = (cnt_div == COUNT_DIV - 1);

// BCD 4桁カウンタ (各桁 0〜9)
reg [3:0] dig0, dig1, dig2, dig3;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        dig0 <= 4'd0;
    end else if (cnt_en) begin
        if (dig0 == 4'd9)
            dig0 <= 4'd0;
        else
            dig0 <= dig0 + 4'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        dig1 <= 4'd0;
    end else if (cnt_en && dig0 == 4'd9) begin
        if (dig1 == 4'd9)
            dig1 <= 4'd0;
        else
            dig1 <= dig1 + 4'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        dig2 <= 4'd0;
    end else if (cnt_en && dig0 == 4'd9 && dig1 == 4'd9) begin
        if (dig2 == 4'd9)
            dig2 <= 4'd0;
        else
            dig2 <= dig2 + 4'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        dig3 <= 4'd0;
    end else if (cnt_en && dig0 == 4'd9 && dig1 == 4'd9 && dig2 == 4'd9) begin
        if (dig3 == 4'd9)
            dig3 <= 4'd0;
        else
            dig3 <= dig3 + 4'd1;
    end
end

// ダイナミック点灯用分周カウンタ
reg [12:0] disp_div;
wire       disp_en;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        disp_div <= 13'd0;
    end else begin
        if (disp_div == DISP_DIV - 1)
            disp_div <= 13'd0;
        else
            disp_div <= disp_div + 13'd1;
    end
end

assign disp_en = (disp_div == DISP_DIV - 1);

// 桁選択カウンタ (0〜3の4桁を巡回)
reg [1:0] dig_sel;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        dig_sel <= 2'd0;
    end else if (disp_en) begin
        dig_sel <= dig_sel + 2'd1;
    end
end

// 表示桁のデータ選択 (マルチプレクサ)
wire [3:0] cur_dig;
assign cur_dig = (dig_sel == 2'd0) ? dig0 :
                 (dig_sel == 2'd1) ? dig1 :
                 (dig_sel == 2'd2) ? dig2 :
                                     dig3 ;

// 7セグメントデコーダ
seg7dec dec0(.din(cur_dig), .seg(seg));

// 桁選択信号 (active LOW, 右端4桁を使用)
assign sel = (dig_sel == 2'd0) ? 8'b11111110 :
             (dig_sel == 2'd1) ? 8'b11111101 :
             (dig_sel == 2'd2) ? 8'b11111011 :
                                 8'b11110111 ;

endmodule
