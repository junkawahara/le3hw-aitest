// debounce.v - チャタリング除去モジュール
// スイッチ入力のチャタリング(バウンス)を除去する
// 一定時間(約20ms)安定した入力値が続いた場合のみ出力を変化させる

module debounce(
    input      clk,
    input      rst_n,
    input      sw_in,
    output reg sw_out
);

parameter CLK_FREQ = 20_000_000;
parameter DB_TIME  = 400_000;      // 20ms @ 20MHz (20M * 0.02)

reg [18:0] cnt;
reg        sw_prev;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        cnt     <= 19'd0;
        sw_prev <= 1'b1;
        sw_out  <= 1'b1;
    end else begin
        if (sw_in != sw_prev) begin
            cnt     <= 19'd0;
            sw_prev <= sw_in;
        end else if (cnt == DB_TIME - 1) begin
            sw_out <= sw_prev;
        end else begin
            cnt <= cnt + 19'd1;
        end
    end
end

endmodule
