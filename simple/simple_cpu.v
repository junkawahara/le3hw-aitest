// simple_cpu.v - SIMPLE/B CPU コア
// 5フェーズ順次実行: p1(IF) → p2(RR) → p3(EX) → p4(MA) → p5(WB)
//
// ブロック図 (SIMPLE設計資料 図2 準拠):
//   PC → メモリ → IR → デコード → レジスタファイル(AR,BR)
//   → ALU/シフタ → DR → メモリ/IO → MDR → レジスタ書き戻し

module simple_cpu(
    input         clk,
    input         rst_n,
    input         exec,
    // メモリインタフェース
    output [15:0] mem_addr,
    input  [15:0] mem_rdata,
    output [15:0] mem_wdata,
    output        mem_we,
    // I/O インタフェース
    input  [15:0] in_data,
    output reg [15:0] out_data,
    output reg        out_we,
    // ステータス
    output        halted
);

// フェーズ定義
localparam P1 = 3'd0; // 命令フェッチ
localparam P2 = 3'd1; // レジスタ読み出し
localparam P3 = 3'd2; // 演算
localparam P4 = 3'd3; // 主記憶アクセス
localparam P5 = 3'd4; // レジスタ書き込み

// 内部レジスタ
reg [15:0] pc, ir, ar, br, dr, mdr;
reg [2:0]  phase;
reg        flag_s, flag_z, flag_c, flag_v;
reg        running;

// ---- 命令デコード ----
wire [1:0] op1   = ir[15:14];
wire [2:0] rs_ra = ir[13:11]; // Rs (演算) / Ra (LD/ST)
wire [2:0] rd_rb = ir[10:8];  // Rd (演算) / Rb (LD/ST/LI)
wire [3:0] op3   = ir[7:4];   // 演算/IO命令コード
wire [3:0] d4    = ir[3:0];   // シフト桁数
wire [7:0] d8    = ir[7:0];   // 即値/変位
wire [2:0] op2   = ir[13:11]; // LI/B 命令コード
wire [2:0] cond  = ir[10:8];  // 条件分岐条件

wire [15:0] sext_d8 = {{8{d8[7]}}, d8};

// 命令種別判定
wire is_alu   = (op1 == 2'b11);
wire is_load  = (op1 == 2'b00);
wire is_store = (op1 == 2'b01);
wire is_li    = (op1 == 2'b10) && (op2 == 3'b000);
wire is_b     = (op1 == 2'b10) && (op2 == 3'b100);
wire is_bcc   = (op1 == 2'b10) && (op2 == 3'b111);

wire is_shift  = is_alu && op3[3] && ~op3[2];           // 1000-1011
wire is_in     = is_alu && (op3 == 4'b1100);
wire is_out    = is_alu && (op3 == 4'b1101);
wire is_hlt    = is_alu && (op3 == 4'b1111);
wire is_alu_rr = is_alu && ~op3[3] &&
                 (op3 != 4'b0111);                       // 0000-0110 (reserved除く)

// ---- レジスタファイル ----
wire [15:0] rf_rd0, rf_rd1;

wire rf_we_need = (is_alu_rr && op3 != 4'b0101) ||       // ALU (CMP除く)
                  is_shift || is_load || is_li || is_in;
wire        rf_we      = (phase == P5) && running && rf_we_need;
wire [2:0]  rf_wr_addr = is_load ? rs_ra : rd_rb;
wire [15:0] rf_wr_data = (is_load || is_in) ? mdr : dr;

regfile rf(
    .clk(clk), .rst_n(rst_n),
    .rd_addr0(rs_ra), .rd_data0(rf_rd0),
    .rd_addr1(rd_rb), .rd_data1(rf_rd1),
    .we(rf_we), .wr_addr(rf_wr_addr), .wr_data(rf_wr_data)
);

// ---- ALU ----
wire [15:0] alu_a = is_li           ? 16'h0000 :
                    (is_b || is_bcc) ? pc       :
                                       br;
wire [15:0] alu_b = is_alu ? ar : sext_d8;
wire [3:0]  alu_op = is_alu ? op3 : 4'h0; // 非ALU命令はADD

wire [15:0] alu_result;
wire        alu_s, alu_z, alu_c, alu_v;

alu alu_inst(
    .a(alu_a), .b(alu_b), .op(alu_op),
    .result(alu_result),
    .flag_s(alu_s), .flag_z(alu_z), .flag_c(alu_c), .flag_v(alu_v)
);

// ---- シフタ ----
wire [15:0] shift_result;
wire        shift_c;

shifter shift_inst(
    .data(br), .d(d4), .op(op3[1:0]),
    .result(shift_result), .flag_c(shift_c)
);

// ---- メモリインタフェース (組み合わせ) ----
// 同期RAM対応: アドレスを1フェーズ前に提示する
//   P5 で次命令アドレス(PC or 分岐先)を提示 → P1 で命令データ取得
//   P3 で実効アドレスを提示               → P4 で LD データ取得
//   P4 で DR を提示 + wren=1             → P4→P5 エッジで ST 書込み
wire [15:0] next_pc_val = (is_b || (is_bcc && branch_taken)) ? dr : pc;

assign mem_addr  = (phase == P3 && (is_load || is_store)) ? alu_result :
                   (phase == P4 && is_store)               ? dr        :
                   (phase == P5)                           ? next_pc_val :
                                                             pc;
assign mem_wdata = ar;
assign mem_we    = (phase == P4) && running && is_store;

// ---- 分岐条件判定 ----
reg branch_taken;
always @(*) begin
    case (cond)
        3'b000:  branch_taken = flag_z;                      // BE
        3'b001:  branch_taken = flag_s ^ flag_v;             // BLT
        3'b010:  branch_taken = flag_z | (flag_s ^ flag_v);  // BLE
        3'b011:  branch_taken = ~flag_z;                     // BNE
        default: branch_taken = 1'b0;
    endcase
end

// ---- ステータス出力 ----
assign halted = ~running;

// ---- exec 立ち上がり検出 ----
reg exec_prev;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) exec_prev <= 1'b0;
    else        exec_prev <= exec;
end
wire exec_rise = exec & ~exec_prev;

// ---- メインステートマシン ----
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        pc       <= 16'h0000;
        ir       <= 16'h0000;
        ar       <= 16'h0000;
        br       <= 16'h0000;
        dr       <= 16'h0000;
        mdr      <= 16'h0000;
        phase    <= P1;
        flag_s   <= 1'b0;
        flag_z   <= 1'b0;
        flag_c   <= 1'b0;
        flag_v   <= 1'b0;
        running  <= 1'b0;
        out_data <= 16'h0000;
        out_we   <= 1'b0;
    end else begin
        out_we <= 1'b0;

        if (~running && exec_rise)
            running <= 1'b1;

        if (running) begin
            case (phase)
                // ---- p1: 命令フェッチ ----
                P1: begin
                    ir    <= mem_rdata;
                    pc    <= pc + 16'd1;
                    phase <= P2;
                end

                // ---- p2: レジスタ読み出し ----
                P2: begin
                    ar    <= rf_rd0; // r[Rs/Ra]
                    br    <= rf_rd1; // r[Rd/Rb]
                    phase <= P3;
                end

                // ---- p3: 演算 ----
                P3: begin
                    if (is_shift)
                        dr <= shift_result;
                    else
                        dr <= alu_result;

                    if (is_alu_rr) begin
                        flag_s <= alu_s;
                        flag_z <= alu_z;
                        flag_c <= alu_c;
                        flag_v <= alu_v;
                    end else if (is_shift) begin
                        flag_s <= shift_result[15];
                        flag_z <= (shift_result == 16'h0000);
                        flag_c <= shift_c;
                        flag_v <= 1'b0;
                    end

                    phase <= P4;
                end

                // ---- p4: 主記憶アクセス / 入出力 ----
                P4: begin
                    if (is_load)
                        mdr <= mem_rdata;
                    if (is_in)
                        mdr <= in_data;
                    if (is_out) begin
                        out_data <= ar;
                        out_we   <= 1'b1;
                    end
                    phase <= P5;
                end

                // ---- p5: レジスタ書き込み / 分岐 ----
                P5: begin
                    if (is_b)
                        pc <= dr;
                    if (is_bcc && branch_taken)
                        pc <= dr;
                    if (is_hlt)
                        running <= 1'b0;
                    phase <= P1;
                end
            endcase
        end
    end
end

endmodule
