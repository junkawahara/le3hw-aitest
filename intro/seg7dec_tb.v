// seg7dec_tb.v - 課題1 テストベンチ
// 0x0〜0xFの全入力パターンを検証

`timescale 1ns / 1ps

module seg7dec_tb;

reg  [3:0] din;
wire [7:0] seg;

seg7dec uut(.din(din), .seg(seg));

integer i;

initial begin
    $display("Time\tdin\tseg");
    $display("----\t---\t--------");
    din = 4'h0;

    for (i = 0; i < 16; i = i + 1) begin
        #100;
        din = i;
        #10;
        $display("%0t\t%h\t%b", $time, din, seg);
    end

    #100;
    $finish;
end

endmodule
