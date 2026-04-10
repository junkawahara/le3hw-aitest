// seg7dec_top.v - 課題1 トップモジュール
// DIPスイッチ4ビット入力 → 7セグメントLED 1桁表示
//
// ピンアサイン: ピンアサイン表を参照して設定すること
//   din[3:0] : DIPスイッチ (負論理: ON=0)
//   seg[7:0] : 7セグメントLEDセグメント出力
//   sel[7:0] : 7セグメントLED桁選択 (1桁のみ選択)

module seg7dec_top(
    input  [3:0] din,
    output [7:0] seg,
    output [7:0] sel
);

// DIPスイッチは負論理なので反転
wire [3:0] din_pos;
assign din_pos = ~din;

// 7セグメントデコーダ
seg7dec dec0(.din(din_pos), .seg(seg));

// 桁選択: 最下位桁(右端)のみ表示 (active LOW)
assign sel = 8'b11111110;

endmodule
