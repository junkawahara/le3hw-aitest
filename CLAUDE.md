# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

京都大学 計算機科学実験及演習3 ハードウェア (le3hw) の課題リポジトリ。Verilog HDLによるFPGA設計。課題については https://isle3hw.kuis.kyoto-u.ac.jp/ を参照。

- **Target**: PowerMedusa MU500-RX/RK (Altera Cyclone IV EP4CE30F23I7N)
- **CAD**: Intel Quartus Prime 20.1 Standard Edition
- **Simulator**: ModelSim-Intel FPGA Starter Edition
- **Clock**: 20MHz oscillator

## Architecture

### 導入課題 (root directory)
7セグメントLED駆動回路とカウンタ。`seg7dec` モジュールは SIMPLE/B の `simple_top.v` でも再利用される。

- Active LOW セグメント出力 (0=点灯, 1=消灯)
- DIPスイッチは負論理 (ON=0)
- ダイナミック点灯: 5000分周 (4kHz) で4桁巡回

### SIMPLE/B CPU (`simple/`)
16ビット・5フェーズ順次実行プロセッサ。

```
P1(IF): IR←mem[PC], PC←PC+1
P2(RR): AR←r[Rs/Ra], BR←r[Rd/Rb]  (非同期レジスタリード)
P3(EX): DR←ALU/Shifter結果
P4(MA): LD→MDR, ST→mem書込, IN/OUT
P5(WB): レジスタ書き戻し, 分岐→PC更新
```

メモリは非同期リード (distributed RAM)。`test.hex` を `$readmemh` で初期化。

命令フォーマット (全16ビット固定長):
- `11|Rs|Rd|op3|d` — 演算/IO (ADD,SUB,AND,OR,XOR,CMP,MOV,SLL-SRA,IN,OUT,HLT)
- `0x|Ra|Rb|d8` — LD(00)/ST(01)
- `10|op2|Rb|d8` — LI(000)/B(100)/Bcc(111)

## Build & Simulation

自動ビルドスクリプトなし。Quartus Prime GUI または以下のコマンドラインで操作:

```bash
# レポートPDFのコンパイル (LuaLaTeX, 2回実行で相互参照解決)
cd /home/htd/le3hw && lualatex intro.tex && lualatex intro.tex
```

テストベンチは分周パラメータを小さい値にオーバーライドしてシミュレーション時間を短縮する設計。

## Conventions

- Verilog記述ルール: 組み合わせ回路は `assign`、順序回路は `always @(posedge clk or negedge rst_n)` + `<=`
- リセットは負論理 (`rst_n`)
- 日本語コメント使用
- レポートは LaTeX (ltjsarticle + LuaLaTeX)
