// simple_top.v - SIMPLE/B トップモジュール (担当B拡張版)
// CPU + メモリ + タイマ + I/Oアドレスデコード + 8桁7セグ表示
//
// I/Oポートマップ:
//   ポート0: IN=DIPスイッチA(SW26), OUT=7セグ出力(下位16bit)
//   ポート1: IN=DIPスイッチB(SW27), OUT=7セグ出力(上位16bit)
//   ポート2: IN=タイマCOUNT,        OUT=タイマCTRL
//   ポート3: IN=タイマoverflow,      OUT=タイマLIMIT
//   ポート4: IN=プッシュスイッチ,    OUT=LED出力(8bit)
//   ポート5: IN=ロータリースイッチ,  OUT=ブザー制御
//
// 7セグ表示モード (ロータリースイッチで切替):
//   モード0: OUTレジスタ値 (デフォルト)
//   モード1: PC値 (デバッグ用)
//   モード2: レジスタr0~r3値
//   モード3: タイマCOUNT値

module simple_top(
    input         clk,
    input         rst_n,
    input         exec,
    input  [15:0] sw,        // DIPスイッチ A+B (負論理)
    input  [3:0]  pushsw,    // プッシュスイッチ (負論理)
    input  [3:0]  rotsw,     // ロータリースイッチ
    output [7:0]  seg,       // 7セグメントLEDセグメント出力
    output [7:0]  sel,       // 7セグメントLED桁選択 (8桁)
    output reg [7:0] led     // LED出力
);

// ---- CPU ↔ メモリ接続 ----
wire [15:0] mem_addr, mem_rdata, mem_wdata;
wire        mem_we;

// ---- CPU ↔ I/O ----
wire [15:0] cpu_out_data;
wire        cpu_out_we;
wire [3:0]  io_port;
wire        io_read, io_write;
wire        cpu_halted;

// ---- デバッグ信号 ----
wire [15:0] debug_pc, debug_r0, debug_r1, debug_r2, debug_r3;

// ---- I/O 入力マルチプレクサ ----
reg [15:0] in_mux;

simple_cpu cpu(
    .clk(clk), .rst_n(rst_n), .exec(exec),
    .mem_addr(mem_addr), .mem_rdata(mem_rdata),
    .mem_wdata(mem_wdata), .mem_we(mem_we),
    .in_data(in_mux),
    .out_data(cpu_out_data), .out_we(cpu_out_we),
    .io_port(io_port), .io_read(io_read), .io_write(io_write),
    .debug_pc(debug_pc),
    .debug_r0(debug_r0), .debug_r1(debug_r1),
    .debug_r2(debug_r2), .debug_r3(debug_r3),
    .halted(cpu_halted)
);

// ---- メモリ (Block RAM) ----
ram memory(
    .clock(clk),
    .address(mem_addr[11:0]),
    .q(mem_rdata),
    .data(mem_wdata),
    .wren(mem_we)
);

// ---- タイマモジュール ----
wire [15:0] timer_count;
wire        timer_overflow;

timer timer_inst(
    .clk(clk), .rst_n(rst_n),
    .wdata(cpu_out_data),
    .we_ctrl(io_write && (io_port == 4'd2)),
    .we_limit(io_write && (io_port == 4'd3)),
    .rd_overflow(io_read && (io_port == 4'd3)),
    .count(timer_count),
    .overflow(timer_overflow)
);

// ---- I/O 入力デコーダ ----
always @(*) begin
    case (io_port)
        4'd0:    in_mux = {8'h00, ~sw[7:0]};        // DIPスイッチ A (負論理反転)
        4'd1:    in_mux = {8'h00, ~sw[15:8]};       // DIPスイッチ B (負論理反転)
        4'd2:    in_mux = timer_count;                // タイマ COUNT
        4'd3:    in_mux = {15'd0, timer_overflow};    // タイマ overflow
        4'd4:    in_mux = {12'h000, ~pushsw};         // プッシュスイッチ (負論理反転)
        4'd5:    in_mux = {12'h000, rotsw};           // ロータリースイッチ
        default: in_mux = 16'h0000;
    endcase
end

// ---- I/O 出力レジスタ ----
reg [15:0] seg_reg_lo;   // 7セグ下位16bit (ポート0)
reg [15:0] seg_reg_hi;   // 7セグ上位16bit (ポート1)

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        seg_reg_lo <= 16'h0000;
        seg_reg_hi <= 16'h0000;
        led        <= 8'h00;
    end else if (io_write) begin
        case (io_port)
            4'd0: seg_reg_lo <= cpu_out_data;
            4'd1: seg_reg_hi <= cpu_out_data;
            4'd4: led        <= cpu_out_data[7:0];
        endcase
    end
end

// 後方互換: 従来の OUT (ポート番号なし) も seg_reg_lo に書き込み
// cpu_out_we は全OUT命令で立つので、ポート0以外の場合もフォールバック
// → io_write でポート区別するのでこの処理は不要

// ---- 7セグ表示 (8桁対応) ----
parameter DISP_DIV = 5000; // 20MHz / 5000 = 4kHz

reg [12:0] disp_cnt;
wire       disp_en = (disp_cnt == DISP_DIV - 1);

always @(posedge clk or negedge rst_n) begin
    if (~rst_n)       disp_cnt <= 13'd0;
    else if (disp_en) disp_cnt <= 13'd0;
    else              disp_cnt <= disp_cnt + 13'd1;
end

reg [2:0] dig_sel;  // 8桁: 0~7
always @(posedge clk or negedge rst_n) begin
    if (~rst_n)       dig_sel <= 3'd0;
    else if (disp_en) dig_sel <= dig_sel + 3'd1;
end

// 表示モード選択 (ロータリースイッチ下位2ビット)
wire [1:0] disp_mode = rotsw[1:0];

// 表示データ選択 (32bit)
// モード2: r0~r3 の下位8ビットを並べて8桁表示
//   桁7(左端)=r3[7:4], 桁6=r3[3:0], ... 桁1=r0[7:4], 桁0(右端)=r0[3:0]
reg [31:0] disp_data;
always @(*) begin
    case (disp_mode)
        2'd0: disp_data = {seg_reg_hi, seg_reg_lo};
        2'd1: disp_data = {16'h0000, debug_pc};
        2'd2: disp_data = {debug_r3[7:0], debug_r2[7:0],
                           debug_r1[7:0], debug_r0[7:0]};
        2'd3: disp_data = {16'h0000, timer_count};
    endcase
end

// 現在の桁のニブル (4bit)
reg [3:0] cur_dig;
always @(*) begin
    case (dig_sel)
        3'd0: cur_dig = disp_data[3:0];
        3'd1: cur_dig = disp_data[7:4];
        3'd2: cur_dig = disp_data[11:8];
        3'd3: cur_dig = disp_data[15:12];
        3'd4: cur_dig = disp_data[19:16];
        3'd5: cur_dig = disp_data[23:20];
        3'd6: cur_dig = disp_data[27:24];
        3'd7: cur_dig = disp_data[31:28];
    endcase
end

seg7dec dec(.din(cur_dig), .seg(seg));

// 8桁の桁選択 (アクティブLOW)
reg [7:0] sel_reg;
always @(*) begin
    case (dig_sel)
        3'd0: sel_reg = 8'b11111110;
        3'd1: sel_reg = 8'b11111101;
        3'd2: sel_reg = 8'b11111011;
        3'd3: sel_reg = 8'b11110111;
        3'd4: sel_reg = 8'b11101111;
        3'd5: sel_reg = 8'b11011111;
        3'd6: sel_reg = 8'b10111111;
        3'd7: sel_reg = 8'b01111111;
    endcase
end
assign sel = sel_reg;

endmodule
