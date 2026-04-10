// simple_tb.v - SIMPLE 拡張版テストベンチ (担当B更新)
// 4サイクルCPU + BAL/BR/ADDI + I/Oポート拡張の検証
//
// テストモード (TEST_MODE パラメータで切替):
//   0: ISA全命令テスト (test_all.hex) - 期待出力: 0008, 0003, 000A, 0014, FFFF
//   1: バブルソートテスト (sort.hex) - 期待出力: 0000~000F (昇順)

`timescale 1ns / 1ps

module simple_tb;

`ifndef TEST_MODE
`define TEST_MODE 0
`endif
`ifndef INIT_FILE
`define INIT_FILE "test_all.hex"
`endif

parameter TEST_MODE = `TEST_MODE;
parameter INIT_FILE = `INIT_FILE;

reg         clk, rst_n, exec;
wire [15:0] mem_addr, mem_rdata, mem_wdata;
wire        mem_we;
wire [15:0] out_data;
wire        out_we;
wire [3:0]  io_port;
wire        io_read, io_write;
wire [15:0] debug_pc, debug_r0, debug_r1, debug_r2, debug_r3;
wire        halted;

simple_cpu cpu(
    .clk(clk), .rst_n(rst_n), .exec(exec),
    .mem_addr(mem_addr), .mem_rdata(mem_rdata),
    .mem_wdata(mem_wdata), .mem_we(mem_we),
    .in_data(16'h00FF),
    .out_data(out_data), .out_we(out_we),
    .io_port(io_port), .io_read(io_read), .io_write(io_write),
    .debug_pc(debug_pc),
    .debug_r0(debug_r0), .debug_r1(debug_r1),
    .debug_r2(debug_r2), .debug_r3(debug_r3),
    .halted(halted)
);

ram #(.INIT_FILE(INIT_FILE)) memory(
    .clock(clk),
    .address(mem_addr[11:0]),
    .q(mem_rdata),
    .data(mem_wdata),
    .wren(mem_we)
);

always #25 clk = ~clk;

// ==== ISA テスト用 (TEST_MODE=0) ====
integer out_count;
reg [15:0] expected_isa [0:4];
initial begin
    expected_isa[0] = 16'h0008;
    expected_isa[1] = 16'h0003;
    expected_isa[2] = 16'h000A;
    expected_isa[3] = 16'h0014;
    expected_isa[4] = 16'hFFFF;
end

// ==== ソートテスト用 (TEST_MODE=1) ====
reg [15:0] expected_sort [0:15];
integer i_init;
initial begin
    for (i_init = 0; i_init < 16; i_init = i_init + 1)
        expected_sort[i_init] = i_init;  // 0, 1, 2, ..., 15
end

// ==== 出力監視 ====
always @(posedge clk) begin
    if (out_we) begin
        if (TEST_MODE == 0) begin
            // ISA テスト
            if (out_count < 5 && out_data == expected_isa[out_count])
                $display("OUT[%0d] = %04h  OK", out_count, out_data);
            else
                $display("OUT[%0d] = %04h  *** MISMATCH (expected %04h) ***",
                         out_count, out_data,
                         (out_count < 5) ? expected_isa[out_count] : 16'hxxxx);
        end else begin
            // ソートテスト
            if (out_count < 16 && out_data == expected_sort[out_count])
                $display("OUT[%0d] = %04h  OK", out_count, out_data);
            else
                $display("OUT[%0d] = %04h  *** MISMATCH (expected %04h) ***",
                         out_count, out_data,
                         (out_count < 16) ? expected_sort[out_count] : 16'hxxxx);
        end
        out_count = out_count + 1;
    end
end

// ==== メインシーケンス ====
initial begin
    clk = 0; rst_n = 1; exec = 0; out_count = 0;
    #50 rst_n = 0; #100 rst_n = 1; #50;

    if (TEST_MODE == 0)
        $display("=== 4-Cycle CPU + ISA Extension Test ===");
    else
        $display("=== Bubble Sort Test ===");

    exec = 1; #50; exec = 0;

    begin : wait_halt
        integer i;
        integer max_cycles;
        max_cycles = (TEST_MODE == 0) ? 2000 : 100000;
        for (i = 0; i < max_cycles; i = i + 1) begin
            @(posedge clk);
            if (halted) begin
                $display("=== CPU Halted (PC=%04h, %0d outputs) ===",
                         cpu.pc, out_count);
                if (TEST_MODE == 0) begin
                    if (out_count == 5)
                        $display("=== ALL TESTS PASSED ===");
                    else
                        $display("=== SOME TESTS MISSING ===");
                end else begin
                    if (out_count == 16)
                        $display("=== SORT TEST PASSED ===");
                    else
                        $display("=== SORT TEST INCOMPLETE (%0d/16) ===", out_count);
                end
                $finish;
            end
        end
    end
    $display("=== Timeout ===");
    $finish;
end

endmodule
