; sort.asm - バブルソート デモプログラム (担当B)
;
; メモリ 0x80~0x8F に16個のデータを格納し、バブルソートを実行。
; ソート完了後、結果を OUT 命令で順に出力する。
;
; レジスタ割り当て:
;   r0: ベースアドレス (0x80)
;   r1: アドレス計算用
;   r2: 内側ループカウンタ j
;   r3: 外側ループ上限 i (15→1)
;   r4: data[j]
;   r5: data[j+1]
;   r6: 表示用カウンタ / 定数
;   r7: (予備)

; ==== 初期化: ベースアドレス設定 ====
        LI   r0, 0x80       ; ベースアドレス

; ==== データ格納: {15, 3, 8, 1, 12, 5, 10, 2, 14, 7, 11, 4, 13, 6, 9, 0} ====
        LI   r1, 15
        ST   r1, 0(r0)
        LI   r1, 3
        ST   r1, 1(r0)
        LI   r1, 8
        ST   r1, 2(r0)
        LI   r1, 1
        ST   r1, 3(r0)
        LI   r1, 12
        ST   r1, 4(r0)
        LI   r1, 5
        ST   r1, 5(r0)
        LI   r1, 10
        ST   r1, 6(r0)
        LI   r1, 2
        ST   r1, 7(r0)
        LI   r1, 14
        ST   r1, 8(r0)
        LI   r1, 7
        ST   r1, 9(r0)
        LI   r1, 11
        ST   r1, 10(r0)
        LI   r1, 4
        ST   r1, 11(r0)
        LI   r1, 13
        ST   r1, 12(r0)
        LI   r1, 6
        ST   r1, 13(r0)
        LI   r1, 9
        ST   r1, 14(r0)
        LI   r1, 0
        ST   r1, 15(r0)

; ==== バブルソート ====
; for i = 15 downto 1:
;   for j = 0 to i-1:
;     if data[j] > data[j+1]: swap(data[j], data[j+1])
;
; ADDI が条件コードを更新するので、外側ループの終了を
; ADDI r3,-1 の Z フラグで判定する (i=0 で Z=1 → BNE不成立 → 脱出)

        LI   r3, 15         ; i = 15

outer:  LI   r2, 0          ; j = 0

inner:  MOV  r1, r0         ; r1 = ベースアドレス
        ADD  r1, r2         ; r1 = base + j
        LD   r4, 0(r1)      ; r4 = data[j]
        LD   r5, 1(r1)      ; r5 = data[j+1]

        CMP  r4, r5         ; data[j] - data[j+1]
        BLE  skip            ; data[j] <= data[j+1] ならスワップ不要

        ; swap
        ST   r5, 0(r1)      ; data[j]   = 旧 data[j+1]
        ST   r4, 1(r1)      ; data[j+1] = 旧 data[j]

skip:   ADDI r2, 1          ; j++
        CMP  r2, r3         ; j < i ?
        BLT  inner           ; yes → 内側ループ継続

        ADDI r3, -1         ; i-- (フラグ更新: i=0 で Z=1)
        BNE  outer           ; i != 0 → 外側ループ継続

; ==== ソート結果表示 ====
; data[0]~data[15] を順に OUT (0, 1, 2, ..., 15)
        LI   r2, 0          ; 表示カウンタ
        LI   r6, 16         ; 要素数

show:   MOV  r1, r0         ; r1 = ベースアドレス
        ADD  r1, r2         ; r1 = base + i
        LD   r4, 0(r1)      ; r4 = data[i]
        OUT  r4              ; 出力
        ADDI r2, 1          ; i++
        CMP  r2, r6         ; i < 16 ?
        BLT  show            ; yes → 表示ループ継続

        HLT
