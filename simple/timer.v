// timer.v - ハードウェアタイマカウンタ (担当B)
//
// レジスタマップ (I/Oポート経由でアクセス):
//   COUNT (R):   現在のカウント値 (16bit)
//   CTRL  (R/W): bit0=動作/停止, bit1=リセット(ワンショット), bit[15:8]=プリスケーラ値
//   LIMIT (R/W): カウント上限値。到達でoverflow=1, COUNT=0
//
// プリスケーラ: clk / (prescaler + 1) の周波数でCOUNTをインクリメント
//   prescaler=0:   20MHz (50ns間隔)
//   prescaler=199: 100kHz (10us間隔)

module timer(
    input         clk,
    input         rst_n,
    input  [15:0] wdata,      // 書き込みデータ
    input         we_ctrl,    // CTRL レジスタ書き込み
    input         we_limit,   // LIMIT レジスタ書き込み
    input         rd_overflow, // overflow 読み出し (クリア用)
    output [15:0] count,      // 現在のカウント値
    output reg    overflow    // カウント到達フラグ
);

// ---- レジスタ ----
reg [15:0] count_reg;
reg [15:0] limit_reg;
reg [15:0] ctrl_reg;

assign count = count_reg;

// CTRL フィールド
wire        timer_en   = ctrl_reg[0];   // 動作/停止
wire [7:0]  prescaler  = ctrl_reg[15:8]; // プリスケーラ値

// ---- プリスケーラカウンタ ----
reg [7:0] pre_cnt;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        count_reg <= 16'h0000;
        limit_reg <= 16'hFFFF;
        ctrl_reg  <= 16'h0000;
        pre_cnt   <= 8'd0;
        overflow  <= 1'b0;
    end else begin
        // CTRL 書き込み
        if (we_ctrl) begin
            ctrl_reg <= wdata;
            // bit1 リセット: COUNT を 0 にクリア (ワンショット)
            if (wdata[1]) begin
                count_reg <= 16'h0000;
                pre_cnt   <= 8'd0;
                overflow  <= 1'b0;
            end
        end

        // CTRL.bit1 自動クリア (書き込みの次サイクル)
        if (ctrl_reg[1] && !we_ctrl)
            ctrl_reg[1] <= 1'b0;

        // LIMIT 書き込み
        if (we_limit)
            limit_reg <= wdata;

        // overflow 読み出しでクリア
        if (rd_overflow)
            overflow <= 1'b0;

        // タイマ動作
        if (timer_en && !ctrl_reg[1]) begin
            if (pre_cnt >= prescaler) begin
                pre_cnt <= 8'd0;
                // メインカウンタ インクリメント
                if (count_reg >= limit_reg) begin
                    count_reg <= 16'h0000;
                    overflow  <= 1'b1;
                end else begin
                    count_reg <= count_reg + 16'd1;
                end
            end else begin
                pre_cnt <= pre_cnt + 8'd1;
            end
        end
    end
end

endmodule
