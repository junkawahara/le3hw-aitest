// simple_cpu.v - SIMPLE プロセッサ (拡張版)
//
// ■ マイクロアーキテクチャ: 4フェーズ実行 (SIMPLE/Bの5フェーズから高速化)
//   PH1 (IF+WB): 命令フェッチ + 前命令のレジスタ書き戻し
//   PH2 (RR):    レジスタ読み出し
//   PH3 (EX):    演算 + ST書込み
//   PH4 (MA):    メモリ読出し / IO / 分岐 / WB準備
//
// ■ ISA拡張 (基本アーキテクチャに追加):
//   BAL Rb, d  (op2=001): r[Rb] = PC, PC = PC + sign_ext(d)  -- Branch And Link
//   BR  Rb     (op2=010): PC = r[Rb]                          -- Branch Register
//   ADDI Rb, d (op2=011): r[Rb] = r[Rb] + sign_ext(d)        -- Add Immediate
//
// ■ 同期RAM対応: アドレスを1フェーズ前に提示
//   PH3: LD/ST用実効アドレス → PH4でデータ取得 / PH3→PH4でST書込み
//   PH4: 次命令アドレス      → PH1で命令取得

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
    output [3:0]  io_port,    // I/Oポート番号 (d4)
    output        io_read,    // IN命令実行中 (PH4)
    output        io_write,   // OUT命令実行中 (PH4)
    // デバッグポート
    output [15:0] debug_pc,   // 現在のPC値
    output [15:0] debug_r0,   // レジスタr0値
    output [15:0] debug_r1,   // レジスタr1値
    output [15:0] debug_r2,   // レジスタr2値
    output [15:0] debug_r3,   // レジスタr3値
    // ステータス
    output        halted
);

// ---- フェーズ定義 (4サイクル) ----
localparam PH1 = 2'd0; // IF + WB
localparam PH2 = 2'd1; // RR
localparam PH3 = 2'd2; // EX + ST write
localparam PH4 = 2'd3; // MA / IO / Branch / WB setup

// ---- 内部レジスタ ----
reg [15:0] pc, ir, ar, br, dr, mdr;
reg [1:0]  phase;
reg        flag_s, flag_z, flag_c, flag_v;
reg        running;

// ---- 書き戻しパイプラインレジスタ ----
reg        wb_rf_we;
reg [2:0]  wb_rf_addr;
reg [15:0] wb_rf_data;  // ALU/Shift/LI/ADDI/BAL 用
reg        wb_use_mdr;  // LD/IN: MDR を使用

// ---- 命令デコード ----
wire [1:0] op1   = ir[15:14];
wire [2:0] rs_ra = ir[13:11];
wire [2:0] rd_rb = ir[10:8];
wire [3:0] op3   = ir[7:4];
wire [3:0] d4    = ir[3:0];
wire [7:0] d8    = ir[7:0];
wire [2:0] op2   = ir[13:11];
wire [2:0] cond  = ir[10:8];

wire [15:0] sext_d8 = {{8{d8[7]}}, d8};

// 命令種別
wire is_alu   = (op1 == 2'b11);
wire is_load  = (op1 == 2'b00);
wire is_store = (op1 == 2'b01);
wire is_li    = (op1 == 2'b10) && (op2 == 3'b000);
wire is_bal   = (op1 == 2'b10) && (op2 == 3'b001); // 拡張
wire is_br    = (op1 == 2'b10) && (op2 == 3'b010); // 拡張
wire is_addi  = (op1 == 2'b10) && (op2 == 3'b011); // 拡張
wire is_b     = (op1 == 2'b10) && (op2 == 3'b100);
wire is_bcc   = (op1 == 2'b10) && (op2 == 3'b111);

wire is_shift  = is_alu && op3[3] && ~op3[2];       // 1000-1011
wire is_in     = is_alu && (op3 == 4'b1100);
wire is_out    = is_alu && (op3 == 4'b1101);
wire is_hlt    = is_alu && (op3 == 4'b1111);
wire is_alu_rr = is_alu && ~op3[3] && (op3 != 4'b0111); // 0000-0110

// 分岐判定
reg branch_taken;
always @(*) begin
    case (cond)
        3'b000:  branch_taken = flag_z;
        3'b001:  branch_taken = flag_s ^ flag_v;
        3'b010:  branch_taken = flag_z | (flag_s ^ flag_v);
        3'b011:  branch_taken = ~flag_z;
        default: branch_taken = 1'b0;
    endcase
end

wire branch_go = is_b || is_bal || is_br || (is_bcc && branch_taken);

// レジスタ書き込みが必要な命令
wire need_rf_write = (is_alu_rr && op3 != 4'b0101) || // ALU (CMP除く)
                     is_shift || is_load || is_li ||
                     is_in || is_bal || is_addi;

// ---- レジスタファイル ----
wire [15:0] rf_rd0, rf_rd1;
wire        rf_we      = (phase == PH1) && running && wb_rf_we;
wire [2:0]  rf_wr_addr = wb_rf_addr;
wire [15:0] rf_wr_data = wb_use_mdr ? mdr : wb_rf_data;

regfile rf(
    .clk(clk), .rst_n(rst_n),
    .rd_addr0(rs_ra), .rd_data0(rf_rd0),
    .rd_addr1(rd_rb), .rd_data1(rf_rd1),
    .we(rf_we), .wr_addr(rf_wr_addr), .wr_data(rf_wr_data)
);

// ---- ALU ----
wire [15:0] alu_a = is_li            ? 16'h0000 :
                    (is_b || is_bcc || is_bal) ? pc :
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

// ---- メモリインタフェース ----
// 同期RAM: PH3でアドレス提示 → PH4でデータ取得 / PH3→PH4でST書込み
//          PH4でnext_pc提示 → PH1で命令取得
wire [15:0] next_pc_val = branch_go ? dr : pc;

assign mem_addr  = (phase == PH3 && (is_load || is_store)) ? alu_result :
                   (phase == PH4)                           ? next_pc_val :
                                                              pc;
assign mem_wdata = ar;
assign mem_we    = (phase == PH3) && running && is_store;

// ---- I/Oポート制御 ----
assign io_port  = d4;
assign io_read  = (phase == PH4) && running && is_in;
assign io_write = (phase == PH4) && running && is_out;

// ---- デバッグポート ----
assign debug_pc = pc;
assign debug_r0 = rf.regs[0];
assign debug_r1 = rf.regs[1];
assign debug_r2 = rf.regs[2];
assign debug_r3 = rf.regs[3];

// ---- ステータス ----
assign halted = ~running;

// ---- exec 立ち上がり検出 ----
reg exec_prev;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) exec_prev <= 1'b0;
    else        exec_prev <= exec;
end
wire exec_rise = exec & ~exec_prev;

// ======== メインFSM ========
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        pc          <= 16'h0000;
        ir          <= 16'h0000;
        ar          <= 16'h0000;
        br          <= 16'h0000;
        dr          <= 16'h0000;
        mdr         <= 16'h0000;
        phase       <= PH1;
        flag_s      <= 1'b0;
        flag_z      <= 1'b0;
        flag_c      <= 1'b0;
        flag_v      <= 1'b0;
        running     <= 1'b0;
        out_data    <= 16'h0000;
        out_we      <= 1'b0;
        wb_rf_we    <= 1'b0;
        wb_rf_addr  <= 3'd0;
        wb_rf_data  <= 16'h0000;
        wb_use_mdr  <= 1'b0;
    end else begin
        out_we <= 1'b0;

        if (~running && exec_rise)
            running <= 1'b1;

        if (running) begin
            case (phase)
                // ============ PH1: 命令フェッチ + 書き戻し ============
                // IR ← mem[next_pc] (PH4で提示済み)
                // WB: rf_we は組み合わせ信号、このエッジでレジスタに書込み
                PH1: begin
                    ir    <= mem_rdata;
                    pc    <= pc + 16'd1;
                    phase <= PH2;
                end

                // ============ PH2: レジスタ読み出し ============
                PH2: begin
                    ar    <= rf_rd0; // r[Rs/Ra]
                    br    <= rf_rd1; // r[Rd/Rb]
                    phase <= PH3;
                end

                // ============ PH3: 演算 + ST書込み ============
                PH3: begin
                    // DR ← 演算結果
                    if (is_shift)
                        dr <= shift_result;
                    else
                        dr <= alu_result;

                    // 条件コード更新
                    if (is_alu_rr || is_addi) begin
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

                    // ST: mem_we=1 (組み合わせ)、PH3→PH4エッジで書込み
                    phase <= PH4;
                end

                // ============ PH4: メモリ読出し / IO / 分岐 / WB準備 ============
                PH4: begin
                    // LD: MDR ← mem[DR] (PH3でアドレス提示済み)
                    if (is_load)
                        mdr <= mem_rdata;

                    // IN / OUT
                    if (is_in)
                        mdr <= in_data;
                    if (is_out) begin
                        out_data <= ar;
                        out_we   <= 1'b1;
                    end

                    // 分岐: PC更新
                    if (branch_go)
                        pc <= dr;

                    // HLT
                    if (is_hlt)
                        running <= 1'b0;

                    // 書き戻し情報をパイプラインレジスタに保存
                    wb_rf_we   <= need_rf_write;
                    wb_rf_addr <= is_load ? rs_ra : rd_rb;
                    wb_use_mdr <= (is_load || is_in);
                    if (is_bal)
                        wb_rf_data <= pc; // 戻りアドレス (= 命令アドレス + 1)
                    else
                        wb_rf_data <= dr;

                    // PH4→PH1エッジ: RAMが next_pc_val をキャプチャ
                    phase <= PH1;
                end
            endcase
        end
    end
end

endmodule
