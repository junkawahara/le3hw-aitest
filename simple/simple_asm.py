#!/usr/bin/env python3
"""simple_asm.py - SIMPLE プロセッサ アセンブラ (担当B)

全命令セット対応 (BAL/BR/ADDI 拡張命令含む)。
ラベル、コメント(;)、.data ディレクティブをサポート。

使い方:
  python3 simple_asm.py input.asm -o output.hex
"""

import sys
import argparse
import re

# レジスタ名 → 番号
REG_MAP = {}
for i in range(8):
    REG_MAP[f'r{i}'] = i
    REG_MAP[f'R{i}'] = i

def parse_register(s):
    """レジスタ名をパースして番号を返す"""
    s = s.strip().rstrip(',')
    if s in REG_MAP:
        return REG_MAP[s]
    raise ValueError(f"不明なレジスタ: {s}")

def parse_imm(s, bits, labels=None, pc=None, pc_relative=False):
    """即値をパースして整数値を返す (符号付き)"""
    s = s.strip()
    if labels and s in labels:
        val = labels[s]
        if pc_relative:
            val = val - (pc + 1)  # PC相対 (PCはフェッチ時に+1済み)
        return val & ((1 << bits) - 1)
    # 数値リテラル
    try:
        if s.startswith('0x') or s.startswith('0X'):
            val = int(s, 16)
        elif s.startswith('0b') or s.startswith('0B'):
            val = int(s, 2)
        else:
            val = int(s)
    except ValueError:
        raise ValueError(f"不明な即値/ラベル: {s}")
    # 範囲チェック
    lo = -(1 << (bits - 1))
    hi = (1 << bits) - 1
    if val < lo or val > hi:
        raise ValueError(f"即値 {val} は {bits}ビット範囲外 [{lo}, {hi}]")
    return val & ((1 << bits) - 1)

def parse_mem_operand(s):
    """'d(Rb)' 形式をパースして (d, rb) を返す"""
    m = re.match(r'\s*(-?\w+)\s*\(\s*(r\d)\s*\)', s, re.IGNORECASE)
    if m:
        return m.group(1), m.group(2)
    raise ValueError(f"不正なメモリオペランド: {s}")

def assemble_line(mnemonic, operands, labels, pc):
    """1行をアセンブルして16ビット機械語を返す"""
    mn = mnemonic.upper()
    ops = [o.strip() for o in operands]

    # ---- 形式 (c): LI Rb, d ----
    if mn == 'LI':
        rb = parse_register(ops[0])
        d = parse_imm(ops[1], 8, labels, pc)
        return (0b10 << 14) | (0b000 << 11) | (rb << 8) | (d & 0xFF)

    # ---- 形式 (c): B d ----
    if mn == 'B':
        d = parse_imm(ops[0], 8, labels, pc, pc_relative=True)
        return (0b10 << 14) | (0b100 << 11) | (0b000 << 8) | (d & 0xFF)

    # ---- 形式 (c): Bcc d ----
    BCC_MAP = {'BE': 0b000, 'BLT': 0b001, 'BLE': 0b010, 'BNE': 0b011}
    if mn in BCC_MAP:
        cond = BCC_MAP[mn]
        d = parse_imm(ops[0], 8, labels, pc, pc_relative=True)
        return (0b10 << 14) | (0b111 << 11) | (cond << 8) | (d & 0xFF)

    # ---- 拡張命令: BAL Rb, d ----
    if mn == 'BAL':
        rb = parse_register(ops[0])
        d = parse_imm(ops[1], 8, labels, pc, pc_relative=True)
        return (0b10 << 14) | (0b001 << 11) | (rb << 8) | (d & 0xFF)

    # ---- 拡張命令: BR Rb ----
    if mn == 'BR':
        rb = parse_register(ops[0])
        return (0b10 << 14) | (0b010 << 11) | (rb << 8) | 0x00

    # ---- 拡張命令: ADDI Rb, d ----
    if mn == 'ADDI':
        rb = parse_register(ops[0])
        d = parse_imm(ops[1], 8, labels, pc)
        return (0b10 << 14) | (0b011 << 11) | (rb << 8) | (d & 0xFF)

    # ---- 形式 (b): LD Ra, d(Rb) ----
    if mn == 'LD':
        ra = parse_register(ops[0])
        d_str, rb_str = parse_mem_operand(ops[1])
        rb = parse_register(rb_str)
        d = parse_imm(d_str, 8, labels, pc)
        return (0b00 << 14) | (ra << 11) | (rb << 8) | (d & 0xFF)

    # ---- 形式 (b): ST Ra, d(Rb) ----
    if mn == 'ST':
        ra = parse_register(ops[0])
        d_str, rb_str = parse_mem_operand(ops[1])
        rb = parse_register(rb_str)
        d = parse_imm(d_str, 8, labels, pc)
        return (0b01 << 14) | (ra << 11) | (rb << 8) | (d & 0xFF)

    # ---- 形式 (a): 演算命令 ----
    ALU_MAP = {
        'ADD': 0b0000, 'SUB': 0b0001, 'AND': 0b0010, 'OR': 0b0011,
        'XOR': 0b0100, 'CMP': 0b0101, 'MOV': 0b0110,
    }
    if mn in ALU_MAP:
        op3 = ALU_MAP[mn]
        rd = parse_register(ops[0])
        rs = parse_register(ops[1])
        return (0b11 << 14) | (rs << 11) | (rd << 8) | (op3 << 4) | 0

    # ---- 形式 (a): シフト命令 ----
    SHIFT_MAP = {'SLL': 0b1000, 'SLR': 0b1001, 'SRL': 0b1010, 'SRA': 0b1011}
    if mn in SHIFT_MAP:
        op3 = SHIFT_MAP[mn]
        rd = parse_register(ops[0])
        d = parse_imm(ops[1], 4, labels, pc)
        return (0b11 << 14) | (0b000 << 11) | (rd << 8) | (op3 << 4) | (d & 0xF)

    # ---- 形式 (a): IN Rd [, port] ----
    if mn == 'IN':
        rd = parse_register(ops[0])
        port = 0
        if len(ops) > 1:
            port = parse_imm(ops[1], 4, labels, pc)
        return (0b11 << 14) | (0b000 << 11) | (rd << 8) | (0b1100 << 4) | (port & 0xF)

    # ---- 形式 (a): OUT Rs [, port] ----
    if mn == 'OUT':
        rs = parse_register(ops[0])
        port = 0
        if len(ops) > 1:
            port = parse_imm(ops[1], 4, labels, pc)
        return (0b11 << 14) | (rs << 11) | (0b000 << 8) | (0b1101 << 4) | (port & 0xF)

    # ---- 形式 (a): HLT ----
    if mn == 'HLT':
        return (0b11 << 14) | (0b000 << 11) | (0b000 << 8) | (0b1111 << 4) | 0

    # ---- ディレクティブ: .word value ----
    if mn == '.WORD':
        val = parse_imm(ops[0], 16, labels, pc)
        return val & 0xFFFF

    raise ValueError(f"不明な命令: {mnemonic}")

def tokenize_line(line):
    """1行をトークン化。ラベル、ニーモニック、オペランドに分離"""
    # コメント除去
    line = line.split(';')[0].strip()
    if not line:
        return None, None, []

    label = None
    # ラベル検出 (行頭の識別子 + コロン)
    m = re.match(r'^(\w+):\s*(.*)', line)
    if m:
        label = m.group(1)
        line = m.group(2).strip()

    if not line:
        return label, None, []

    parts = line.split(None, 1)
    mnemonic = parts[0]
    operands = []
    if len(parts) > 1:
        # カンマ区切りでオペランド分割 (ただし括弧内のカンマは無視)
        raw = parts[1].strip()
        # d(Rb) 形式を1つのオペランドとして扱うため、賢く分割
        # 簡易実装: 最初のカンマで分割 (LD/STは2オペランド目が d(Rb))
        depth = 0
        current = ''
        for ch in raw:
            if ch == '(':
                depth += 1
                current += ch
            elif ch == ')':
                depth -= 1
                current += ch
            elif ch == ',' and depth == 0:
                operands.append(current.strip())
                current = ''
            else:
                current += ch
        if current.strip():
            operands.append(current.strip())

    return label, mnemonic, operands

def assemble(source):
    """アセンブリソースをアセンブルしてhexリストを返す"""
    lines = source.split('\n')

    # パス1: ラベルアドレスを収集
    labels = {}
    pc = 0
    for line in lines:
        label, mnemonic, operands = tokenize_line(line)
        if label:
            labels[label] = pc
        if mnemonic:
            pc += 1

    # パス2: 機械語を生成
    result = []
    pc = 0
    for lineno, line in enumerate(lines, 1):
        label, mnemonic, operands = tokenize_line(line)
        if mnemonic:
            try:
                code = assemble_line(mnemonic, operands, labels, pc)
                result.append((pc, code, line.strip()))
                pc += 1
            except ValueError as e:
                print(f"エラー (行{lineno}): {e}", file=sys.stderr)
                print(f"  {line.rstrip()}", file=sys.stderr)
                sys.exit(1)

    return result

def main():
    parser = argparse.ArgumentParser(description='SIMPLE プロセッサ アセンブラ')
    parser.add_argument('input', help='入力アセンブリファイル (.asm)')
    parser.add_argument('-o', '--output', default=None, help='出力hexファイル')
    parser.add_argument('-l', '--listing', action='store_true', help='リスティング表示')
    args = parser.parse_args()

    with open(args.input, 'r') as f:
        source = f.read()

    result = assemble(source)

    # リスティング出力
    if args.listing:
        for pc, code, src in result:
            print(f"{pc:04X}: {code:04X}  {src}")

    # hex ファイル出力
    output = args.output or args.input.rsplit('.', 1)[0] + '.hex'
    with open(output, 'w') as f:
        for pc, code, src in result:
            f.write(f"{code:04X}\n")

    print(f"アセンブル完了: {len(result)} 語 → {output}", file=sys.stderr)

if __name__ == '__main__':
    main()
