// simple_tb.v - SIMPLE/B テストベンチ (同期RAM対応)
// ram_sim.v の同期RAMモデルを使用して検証

`timescale 1ns / 1ps

module simple_tb;

reg         clk;
reg         rst_n;
reg         exec;
wire [15:0] mem_addr, mem_rdata, mem_wdata;
wire        mem_we;
wire [15:0] out_data;
wire        out_we;
wire        halted;

// ---- CPU ----
simple_cpu cpu(
    .clk(clk), .rst_n(rst_n), .exec(exec),
    .mem_addr(mem_addr), .mem_rdata(mem_rdata),
    .mem_wdata(mem_wdata), .mem_we(mem_we),
    .in_data(16'h00FF),
    .out_data(out_data), .out_we(out_we),
    .halted(halted)
);

// ---- 同期RAMモデル (ram.v互換) ----
ram #(.INIT_FILE("test_basic.hex")) memory(
    .clock(clk),
    .address(mem_addr[11:0]),
    .q(mem_rdata),
    .data(mem_wdata),
    .wren(mem_we)
);

// ---- クロック (20MHz: 周期50ns) ----
always #25 clk = ~clk;

// ---- 出力監視 ----
always @(posedge clk) begin
    if (out_we)
        $display("Time %0t: OUT = %h (%0d)", $time, out_data, out_data);
end

// ---- テストシナリオ ----
initial begin
    clk   = 1'b0;
    rst_n = 1'b1;
    exec  = 1'b0;

    // リセット
    #50  rst_n = 1'b0;
    #100 rst_n = 1'b1;
    #50;

    // 実行開始
    $display("--- Execution Start ---");
    exec = 1'b1;
    #50;
    exec = 1'b0;

    // HLT まで待機 (最大200サイクル)
    begin : wait_halt
        integer i;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (halted) begin
                $display("--- CPU Halted (PC=%h) ---", cpu.pc);
                $finish;
            end
        end
    end

    $display("--- Timeout ---");
    $finish;
end

endmodule
