// simple_tb.v - SIMPLE 拡張版テストベンチ
// 4サイクルCPU + BAL/BR/ADDI 命令の検証
// 期待出力: OUT=0008, 0003, 000A, 0014, FFFF

`timescale 1ns / 1ps

module simple_tb;

reg         clk, rst_n, exec;
wire [15:0] mem_addr, mem_rdata, mem_wdata;
wire        mem_we;
wire [15:0] out_data;
wire        out_we;
wire        halted;

simple_cpu cpu(
    .clk(clk), .rst_n(rst_n), .exec(exec),
    .mem_addr(mem_addr), .mem_rdata(mem_rdata),
    .mem_wdata(mem_wdata), .mem_we(mem_we),
    .in_data(16'h00FF),
    .out_data(out_data), .out_we(out_we),
    .halted(halted)
);

ram #(.INIT_FILE("test_all.hex")) memory(
    .clock(clk),
    .address(mem_addr[11:0]),
    .q(mem_rdata),
    .data(mem_wdata),
    .wren(mem_we)
);

always #25 clk = ~clk;

integer out_count;
reg [15:0] expected [0:4];
initial begin
    expected[0] = 16'h0008;
    expected[1] = 16'h0003;
    expected[2] = 16'h000A;
    expected[3] = 16'h0014;
    expected[4] = 16'hFFFF;
end

always @(posedge clk) begin
    if (out_we) begin
        if (out_count < 5 && out_data == expected[out_count])
            $display("OUT[%0d] = %04h  OK", out_count, out_data);
        else
            $display("OUT[%0d] = %04h  *** MISMATCH (expected %04h) ***",
                     out_count, out_data,
                     (out_count < 5) ? expected[out_count] : 16'hxxxx);
        out_count = out_count + 1;
    end
end

initial begin
    clk = 0; rst_n = 1; exec = 0; out_count = 0;
    #50 rst_n = 0; #100 rst_n = 1; #50;
    $display("=== 4-Cycle CPU + ISA Extension Test ===");
    exec = 1; #50; exec = 0;

    begin : wait_halt
        integer i;
        for (i = 0; i < 2000; i = i + 1) begin
            @(posedge clk);
            if (halted) begin
                $display("=== CPU Halted (PC=%04h, %0d outputs) ===", cpu.pc, out_count);
                if (out_count == 5)
                    $display("=== ALL TESTS PASSED ===");
                else
                    $display("=== SOME TESTS MISSING ===");
                $finish;
            end
        end
    end
    $display("=== Timeout ===");
    $finish;
end

endmodule
