# SIMPLE プロセッサ拡張 — 担当B 実装仕様書

## 役割分担

| 担当 | 内容 | 状態 |
|------|------|------|
| A | ISA拡張 (BAL/BR/ADDI)、4サイクル化 | **完了** |
| B | タイマ、I/O拡張、7セグ改善、応用プログラム、アセンブラ対応 | 未着手 |

## 現在のCPU仕様 (担当Aの実装済み部分)

### 4サイクル実行

```
PH1 (IF+WB) → PH2 (RR) → PH3 (EX+ST) → PH4 (MA/IO/Branch)
```

- 全命令が4サイクルで実行される (5サイクルから25%高速化)
- 同期RAM (Block RAM) 対応済み

### 追加命令

| 命令 | 形式 | エンコーディング | 機能 |
|------|------|----------------|------|
| BAL Rb, d | (c) op2=001 | `10_001_Rb_dddddddd` | `r[Rb]=PC; PC=PC+sign_ext(d)` |
| BR Rb | (c) op2=010 | `10_010_Rb_00000000` | `PC=r[Rb]` |
| ADDI Rb, d | (c) op2=011 | `10_011_Rb_dddddddd` | `r[Rb]=r[Rb]+sign_ext(d); flags更新` |

### ファイル構成

```
simple/
├── simple_cpu.v   ← 4サイクルCPU (担当A実装済み)
├── alu.v          ← ALU (変更なし)
├── shifter.v      ← シフタ (変更なし)
├── regfile.v      ← レジスタファイル (変更なし)
├── ram.v          ← Quartus Block RAM IP
├── ram_sim.v      ← シミュレーション用同期RAMモデル
├── simple_top.v   ← トップモジュール (担当Bが拡張)
├── seg7dec.v      ← 7セグデコーダ
└── test_all.hex   ← 全命令テスト
```

---

## 担当B 実装項目

### 1. タイマモジュール (`timer.v`)

#### 概要
ハードウェアタイマカウンタを実装する。ソフトウェア遅延ループを不要にし、正確な時間計測を可能にする。

#### インタフェース

```verilog
module timer(
    input         clk,
    input         rst_n,
    input  [15:0] wdata,    // 書き込みデータ
    input         we_ctrl,  // 制御レジスタ書き込み
    input         we_limit, // リミット値書き込み
    output [15:0] count,    // 現在のカウント値 (IN命令で読み出し)
    output        overflow  // カウント到達フラグ
);
```

#### レジスタ

| アドレス | 名前 | R/W | 機能 |
|---------|------|-----|------|
| 0 | COUNT | R | 現在のカウント値 (16ビット) |
| 1 | CTRL | R/W | bit0: 動作/停止, bit1: リセット, bit[15:8]: プリスケーラ値 |
| 2 | LIMIT | R/W | カウント上限値。到達するとoverflowフラグが立ちCOUNTが0に戻る |

#### 動作仕様

1. CTRL.bit0 = 1 のとき、プリスケーラで分周されたクロックでCOUNTをインクリメント
2. COUNT が LIMIT に達したら overflow = 1 となり、COUNT を 0 にリセット
3. CTRL.bit1 に 1 を書くとCOUNTを即座に0にリセット (ワンショット、自動クリア)
4. プリスケーラ: 20MHz / (CTRL[15:8] + 1) の周波数でカウント
   - CTRL[15:8] = 0: 20MHz (50ns間隔)
   - CTRL[15:8] = 199: 100kHz (10us間隔)
   - CTRL[15:8] = 255: 約78kHz

#### 実装のポイント

- プリスケーラカウンタ (8ビット) が CTRL[15:8] に達したら 0 に戻し、メインカウンタをインクリメント
- overflow フラグは IN 命令で読み出されたら (または CTRL リセットで) クリア

---

### 2. I/Oアドレス空間の拡張 (`simple_top.v` 修正)

#### 概要
現在の IN/OUT 命令は単一の入出力先に固定されている。I/Oアドレスを導入し、複数デバイスを切り替え可能にする。

#### アドレスマッピング

IN/OUT 命令の `d` フィールド (I[3:0]) をI/Oポート番号として使用する。

| ポート | IN (読み出し) | OUT (書き込み) |
|--------|-------------|--------------|
| 0 | DIPスイッチ A (SW26, 8bit) | 7セグ出力レジスタ (下位16bit) |
| 1 | DIPスイッチ B (SW27, 8bit) | 7セグ出力レジスタ (上位16bit) |
| 2 | タイマ COUNT値 | タイマ CTRL レジスタ |
| 3 | タイマ overflow (bit0) | タイマ LIMIT レジスタ |
| 4 | プッシュスイッチ状態 | LED出力 (8bit) |
| 5 | ロータリースイッチ値 | ブザー制御 |

#### CPUの変更

`simple_cpu.v` の OUT/IN 処理で `d4` (I[3:0]) をポート番号として外部に出力する。

```verilog
// simple_cpu.v に追加する出力ポート
output [3:0] io_port,     // I/Oポート番号
output       io_read,     // IN命令実行中 (PH4)
output       io_write     // OUT命令実行中 (PH4)
```

#### simple_top.v での接続

```verilog
// ポートデコーダ
always @(*) begin
    case (io_port)
        4'd0: in_mux = dipsw_a;
        4'd1: in_mux = dipsw_b;
        4'd2: in_mux = timer_count;
        4'd3: in_mux = {15'd0, timer_overflow};
        4'd4: in_mux = push_sw;
        default: in_mux = 16'h0000;
    endcase
end

always @(posedge clk) begin
    if (io_write) begin
        case (io_port)
            4'd0: seg_reg[15:0]  <= cpu_out_data;
            4'd1: seg_reg[31:16] <= cpu_out_data;
            4'd2: timer_ctrl     <= cpu_out_data;
            4'd3: timer_limit    <= cpu_out_data;
            4'd4: led_reg        <= cpu_out_data[7:0];
        endcase
    end
end
```

#### 実装のポイント

- `simple_cpu.v` に `io_port` 出力を追加する必要がある (= `d4` を外部に出すだけ)
- `in_data` はポートに応じたマルチプレクス結果を供給
- 後方互換: ポート0はデフォルトのDIPスイッチ/7セグなので、既存プログラムは変更不要

---

### 3. 7セグ表示の改善 (`simple_top.v` 修正)

#### 概要
現在は OUT 命令の出力を4桁hex表示するのみ。8桁フル表示とモード切替を追加する。

#### 仕様

- **8桁表示**: OUT ポート0 (下位16bit) + ポート1 (上位16bit) で32bit = 8桁hex表示
- **表示モード** (ロータリースイッチで切替):
  - モード0: OUT レジスタ値 (デフォルト)
  - モード1: PC値 (デバッグ用)
  - モード2: レジスタr0〜r3の値 (各4bit hex, 下位のみ)
  - モード3: タイマCOUNT値

#### 実装のポイント

- ダイナミック点灯を8桁に拡張 (dig_sel を 3ビットに)
- ロータリースイッチの値を読み取り、表示データのマルチプレクサを切替
- CPUの内部信号 (PC, レジスタ値) を観測するためのデバッグポートが必要
  - `simple_cpu.v` に `debug_pc`, `debug_reg` 出力を追加するか、
    既存の信号を `simple_top.v` から階層参照 (`cpu.pc` 等) する

---

### 4. 応用プログラム: バブルソート

#### 概要
メモリ上の配列をバブルソートし、結果を7セグLEDに表示するデモプログラム。

#### プログラム仕様

```
データ領域: アドレス 0x80〜0x8F (16要素)
初期値:     {15, 3, 8, 1, 12, 5, 10, 2, 14, 7, 11, 4, 13, 6, 9, 0}

アルゴリズム:
  for i = 15 downto 1:
    for j = 0 to i-1:
      if data[j] > data[j+1]:
        swap(data[j], data[j+1])

ソート完了後:
  各要素を OUT 命令で出力 (0, 1, 2, ..., 15 の順)
```

#### 使用命令

- `LI` でアドレス/定数をロード
- `LD`/`ST` でメモリアクセス
- `ADDI` でポインタインクリメント
- `CMP`/`BLT`/`BNE` でループと条件分岐
- `BAL`/`BR` でswap関数の呼び出し/復帰
- `OUT` で結果表示

#### アセンブリコード (擬似コード)

```asm
; 初期化
        LI r0, 0x80     ; ベースアドレス (data[0])
        LI r1, 16       ; 配列長
        ; data[] をメモリに格納 (LI + ST の繰り返し)

; バブルソート外側ループ
outer:  ADDI r1, -1     ; i--
        BE done          ; i == 0 なら終了
        LI r2, 0         ; j = 0
inner:  ; data[j] と data[j+1] を LD でロード
        ; CMP で比較
        ; BLE skip (data[j] <= data[j+1] ならスキップ)
        ; swap: ST で交換
skip:   ADDI r2, 1       ; j++
        CMP r2, r1
        BLT inner
        B outer

done:   ; 結果表示ループ
        LI r2, 0
show:   LD r3, 0(r0)     ; r3 = data[r2] (アドレス計算が必要)
        OUT r3
        ADDI r2, 1
        ...
        HLT
```

#### 実装のポイント

- ADDI 命令 (即値-128〜+127) を活用してループカウンタを効率化
- BAL/BR を使って swap をサブルーチン化すると可読性が上がる
- LD/ST のベースレジスタ + 変位でメモリアクセス
- タイマ使用で実行時間を計測し、レポートに記載

---

### 5. アセンブラ対応

#### 概要
`simple_assembler` (Python) に新命令を追加する。

#### 追加するニーモニック

| ニーモニック | エンコーディング | アセンブラ記法 |
|-------------|----------------|-------------|
| `BAL Rb, label` | `10_001_Rb_dddddddd` | `BAL R7, func` (ラベルからPC相対変位を計算) |
| `BR Rb` | `10_010_Rb_00000000` | `BR R7` |
| `ADDI Rb, imm` | `10_011_Rb_dddddddd` | `ADDI R0, 1` / `ADDI R1, -1` |

#### 実装箇所

`simple_assembler` のソースコードで、命令パーサーに上記3命令を追加する。
形式は LI/B と同じ format (c) なので、既存の LI/B パーサーを参考に実装できる。

---

## テスト方法

### シミュレーション (iverilog)

```bash
cd simple
iverilog -o sim.out simple_tb.v simple_cpu.v alu.v shifter.v regfile.v ram_sim.v
vvp sim.out
```

### FPGA実装

1. Quartus で `simple_top.v` + 全モジュール + `ram.v` をプロジェクトに追加
2. `run.mif` にプログラムを書き込み
3. ピンアサインを設定
4. コンパイル → 実機書き込み

---

## スケジュール目安

| 期間 | 担当B タスク |
|------|------------|
| 1週目 | タイマモジュール実装 + テスト |
| 2週目 | I/Oアドレス拡張 + 7セグ改善 |
| 3週目 | ソートプログラム作成 + アセンブラ対応 |
| 4週目 | 統合テスト + レポート作成 |
